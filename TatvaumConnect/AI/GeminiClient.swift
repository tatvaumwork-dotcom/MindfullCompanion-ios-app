import Foundation
import Observation
import os

/// One message of a conversation sent to the model. Roles: "system", "user", "assistant".
struct LlmMessage: Codable, Equatable {
    let role: String
    let content: String
}

/// Errors shown to the user in plain language.
enum AiError: Error, LocalizedError {
    case notConfigured, rejected, busy, rateLimited
    case network(String)
    case server(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "The AI isn't set up in this version of the app."
        case .rejected: "The AI service isn't available right now. Please try again later."
        case .busy: "The AI is very busy right now. Please try again in a minute."
        case .rateLimited: "Lots of people are chatting right now. Please try again in a minute."
        case .network: "Couldn't connect. Check your internet connection and try again."
        case .server(let code, _): "The AI had a problem (\(code)). Please try again."
        case .badResponse: "The AI returned an unexpected response. Please try again."
        }
    }
}

/// Google Gemini via its OpenAI-compatible Chat Completions endpoint, using the app's own API key.
///
/// Models are never hardcoded: the key's model list is fetched once and ranked (cheapest capable
/// first). Each request goes to the most available model: ones that were just busy or out of quota
/// sit out briefly while the next takes over, and retired models are dropped automatically.
/// `status` drives the indicator in Chat. The bundle id is sent with every request so the key can
/// be restricted to this app in Google Cloud Console.
@MainActor @Observable
final class GeminiClient {
    /// What the indicator at the top of Chat shows.
    enum Status { case Checking, Ready, Busy, Unavailable, Offline }

    private(set) var status: Status
    var isConfigured: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    @ObservationIgnored private let apiKey: String
    @ObservationIgnored private var models: [String]
    @ObservationIgnored private var lastCheck = Date.distantPast
    @ObservationIgnored private var health: [String: Health] = [:]

    private struct Health { var failStreak = 0; var failedAt = Date.distantPast }

    init(apiKey: String = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String ?? "") {
        self.apiKey = apiKey
        status = apiKey.trimmingCharacters(in: .whitespaces).isEmpty ? .Unavailable : .Checking
        models = (UserDefaults.standard.string(forKey: Self.keyModels) ?? "").split(separator: ",").map(String.init)
    }

    // MARK: Public API

    /// Non-streaming completion. Returns the assistant text.
    func complete(_ messages: [LlmMessage]) async throws -> String {
        let (bytes, http) = try await sendChat(messages, stream: false)
        let data = try await check(bytes, http)
        guard let text = Self.parseCompletion(data) else { throw AiError.badResponse }
        return text
    }

    /// Streaming completion: yields text pieces as they arrive. Cancelling the consumer cancels the request.
    func stream(_ messages: [LlmMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                do {
                    let (bytes, http) = try await sendChat(messages, stream: true)
                    _ = try await check(bytes, http, consume: false)
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        switch Self.parseStreamChunk(payload) {
                        case .skip: continue
                        case .delta(let d): cont.yield(d)
                        case .error(let m): throw AiError.server(500, m)
                        }
                    }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    /// Refreshes the indicator with a tiny one-token request, at most every few minutes unless `force`d.
    func checkAvailability(force: Bool = false) async {
        guard isConfigured else { return }
        if !force && Date().timeIntervalSince(lastCheck) < 180 { return }
        lastCheck = Date()
        status = .Checking
        do {
            let (bytes, http) = try await sendChat([LlmMessage(role: "user", content: "ping")], stream: false, maxTokens: 1)
            _ = try await check(bytes, http)
        } catch {
            // sendChat/check already set the status.
            Self.log.warning("availability check failed: \(error.localizedDescription)")
        }
    }

    // MARK: Parsing helpers (pure)

    enum Chunk: Equatable { case skip, delta(String), error(String) }

    nonisolated static func parseCompletion(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let c = (root["choices"] as? [[String: Any]])?.first,
              let text = (c["message"] as? [String: Any])?["content"] as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One SSE `data:` payload. Malformed chunks are skipped; `error` objects abort the stream.
    nonisolated static func parseStreamChunk(_ payload: String) -> Chunk {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return .skip }
        if let err = obj["error"] as? [String: Any] { return .error(err["message"] as? String ?? "Stream failed") }
        if let d = ((obj["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?["content"] as? String, !d.isEmpty {
            return .delta(d)
        }
        return .skip
    }

    /// Stable Flash / Flash-Lite models only (no -preview / -exp / dated suffixes).
    nonisolated private static let stableFlash = #/^(?:models/)?gemini-(\d+(?:\.\d+)?)-flash(-lite)?$/#

    /// Flash-Lite first (cheapest; plenty for a companion chat), newest first; then full Flash as fallback.
    nonisolated static func rankModels(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.compactMap { id -> (Double, Bool, String)? in
            guard let m = id.wholeMatch(of: stableFlash) else { return nil }
            return (Double(m.1) ?? 0, m.2 != nil, id.hasPrefix("models/") ? String(id.dropFirst(7)) : id)
        }
        .sorted { $0.1 != $1.1 ? $0.1 : $0.0 > $1.0 }
        .map(\.2)
        .filter { seen.insert($0).inserted }
    }

    /// Pulls a replacement model out of a 404 like "...use models/gemini-3.5-flash-lite for...".
    nonisolated static func suggestedModel(_ message: String) -> String? {
        message.matches(of: #/models/(gemini-[a-z0-9.\-]+)/#).last.map { String($0.1) }
    }

    // MARK: Models & health

    private static let log = Logger(subsystem: "com.tatvaum.connect", category: "Gemini")
    private static let keyModels = "gemini.models"
    /// Only used if the key's model list has no stable Flash model at all.
    private static let fallbackModel = "gemini-flash-lite-latest"
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/openai"
    private static let overloaded: Set<Int> = [500, 502, 503, 504]
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        return URLSession(configuration: c)
    }()

    private func saveModels(_ list: [String]) {
        models = list
        UserDefaults.standard.set(list.joined(separator: ","), forKey: Self.keyModels)
    }

    private func cooldown(_ streak: Int) -> TimeInterval { min(30 * Double(1 << min(max(streak - 1, 0), 5)), 600) }

    private func isCoolingDown(_ model: String) -> Bool {
        guard let h = health[model] else { return false }
        return h.failStreak > 0 && Date().timeIntervalSince(h.failedAt) < cooldown(h.failStreak)
    }

    /// Candidate models, most available first: healthy ones before ones sitting out after a failure.
    private func byAvailability() -> [String] {
        let all = models.isEmpty ? [Self.fallbackModel] : models
        let healthy = all.filter { !isCoolingDown($0) }
        let cooling = all.filter(isCoolingDown).sorted { (health[$0]?.failedAt ?? .distantPast) < (health[$1]?.failedAt ?? .distantPast) }
        return healthy + cooling
    }

    private func listModels() async throws -> [String] {
        let (bytes, http) = try await execute(authed(URLRequest(url: URL(string: "\(Self.baseURL)/models")!)))
        let data = try await check(bytes, http)
        let ids = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]])?
            .compactMap { $0["id"] as? String } ?? []
        let ranked = Self.rankModels(ids)
        Self.log.info("models: \(ranked.joined(separator: ","))")
        return ranked
    }

    /// Sends a chat request, trying models in order of availability:
    ///  - 429 / 500 / 502 / 503 / 504 (busy or out of quota): mark the model and move on to the next.
    ///  - 404 (model retired): drop it for good and try Google's suggested replacement next.
    /// If every model is busy, waits briefly and gives the two best one more try.
    /// Returns the first response that is none of these (it may still be an error for `check`).
    private func sendChat(_ messages: [LlmMessage], stream: Bool, maxTokens: Int? = nil)
        async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        guard isConfigured else { throw AiError.notConfigured }
        do { if models.isEmpty { saveModels(try await listModels()) } }
        catch let e as AiError { status = statusFor(e); throw e }
        let preferred = byAvailability().first
        var tried = Set<String>()
        var last: (URLSession.AsyncBytes, HTTPURLResponse)?
        var usedFallback = false
        for round in 0...1 {
            if round == 1 { try await Task.sleep(for: .milliseconds(1500)) }
            var queue = round == 0 ? byAvailability() : Array(byAvailability().prefix(2))
            while !queue.isEmpty {
                let model = queue.removeFirst()
                if round == 0 && !tried.insert(model).inserted { continue }
                let resp: (URLSession.AsyncBytes, HTTPURLResponse)
                do { resp = try await execute(try chatRequest(messages, stream: stream, model: model, maxTokens: maxTokens)) }
                catch let e as AiError { status = statusFor(e); throw e }
                last = resp
                switch resp.1.statusCode {
                case 404:
                    var body = ""
                    for try await line in resp.0.lines { body += line + "\n"; if body.count > 8192 { break } }
                    Self.log.warning("\(model) retired (404), dropping it")
                    saveModels(models.filter { $0 != model })
                    if let s = Self.suggestedModel(body), !tried.contains(s) { queue.insert(s, at: 0) }
                    usedFallback = true
                case 429, 500, 502, 503, 504:
                    Self.log.warning("\(model) busy (\(resp.1.statusCode)); trying the next model")
                    health[model, default: Health()].failStreak += 1
                    health[model]!.failedAt = Date()
                    usedFallback = true
                default:
                    if (200..<300).contains(resp.1.statusCode) {
                        health[model] = Health()
                        if !models.contains(model) {
                            let r = Self.rankModels(models + [model])
                            saveModels(r.isEmpty ? models + [model] : r)
                        }
                        status = usedFallback || model != preferred ? .Busy : .Ready
                    }
                    return resp
                }
            }
        }
        status = .Unavailable
        return last!
    }

    private func statusFor(_ e: AiError) -> Status {
        if case .network = e { return .Offline }
        return .Unavailable
    }

    // MARK: HTTP

    private func chatRequest(_ messages: [LlmMessage], stream: Bool, model: String, maxTokens: Int?) throws -> URLRequest {
        var body: [String: Any] = ["model": model, "stream": stream,
                                   "messages": messages.map { ["role": $0.role, "content": $0.content] }]
        if let maxTokens { body["max_tokens"] = maxTokens }
        var r = authed(URLRequest(url: URL(string: "\(Self.baseURL)/chat/completions")!))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream { r.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    /// Key plus the header Google checks when a key is restricted to an iOS app.
    private func authed(_ r: URLRequest) -> URLRequest {
        var r = r
        r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let id = Bundle.main.bundleIdentifier { r.setValue(id, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
        return r
    }

    private func execute(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        do {
            let (bytes, resp) = try await Self.session.bytes(for: request)
            guard let http = resp as? HTTPURLResponse else { throw AiError.badResponse }
            return (bytes, http)
        } catch is CancellationError { throw CancellationError()
        } catch let e as URLError where e.code == .cancelled { throw CancellationError()
        } catch let e as AiError { throw e
        } catch { throw AiError.network(error.localizedDescription) }
    }

    /// Maps errors. Google reports a bad key as 400 (not 401); streaming errors come as a JSON array.
    /// On success returns the body (read unless `consume` is false, for streaming).
    @discardableResult
    private func check(_ bytes: URLSession.AsyncBytes, _ http: HTTPURLResponse, consume: Bool = true) async throws -> Data {
        var data = Data()
        if (200..<300).contains(http.statusCode) {
            if consume { for try await b in bytes { data.append(b) } }
            return data
        }
        for try await b in bytes { data.append(b) }
        let root = try? JSONSerialization.jsonObject(with: data)
        let errObj = ((root as? [Any])?.first as? [String: Any] ?? root as? [String: Any])?["error"] as? [String: Any]
        let message = errObj?["message"] as? String ?? ""
        Self.log.warning("HTTP \(http.statusCode): \(message)")
        let keyProblem = message.contains(#/(?i)\b(api|auth)\s+key\b/#)
        let code = http.statusCode
        if code == 401 || code == 403 || keyProblem { status = .Unavailable }
        if code == 401 || code == 403 || (code == 400 && keyProblem) { throw AiError.rejected }
        if code == 429 { throw AiError.rateLimited }
        if Self.overloaded.contains(code) { throw AiError.busy }
        throw AiError.server(code, message)
    }
}
