import Foundation
import Observation

/// The live conversation. App-scoped so a reply keeps streaming across view changes,
/// and persisted after each turn so it survives process death.
@MainActor @Observable
final class ChatSession {
    private(set) var messages: [ChatMessage]
    private(set) var isGenerating = false
    /// One-off message for a toast (e.g. "3 items added to your profile"); the UI clears it.
    var notice: String?

    @ObservationIgnored private let llm: LLMService
    @ObservationIgnored private let profileStore: ProfileStore
    @ObservationIgnored private let historyStore: HistoryStore
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    /// Hard ceiling on reply length; the stream is cancelled once exceeded.
    private let maxResponseWords = 300

    init(llm: LLMService, profileStore: ProfileStore, historyStore: HistoryStore) {
        self.llm = llm; self.profileStore = profileStore; self.historyStore = historyStore
        messages = historyStore.restoredActiveMessages
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        let history = messages
        messages.append(ChatMessage(role: .user, content: text))

        // Input-side guardrail: disallowed content never reaches the model.
        if let v = ChatGuardrail.evaluate(text) {
            messages.append(ChatMessage(role: .assistant, content: ChatGuardrail.fallbackMessage(v)))
            save(); return
        }

        let replyID = newID()
        messages.append(ChatMessage(id: replyID, role: .assistant, content: ""))
        let systemPrompt = LLMService.buildSystemPrompt(profileStore.profile, Array(historyStore.summaries.prefix(5)))

        isGenerating = true
        streamTask = Task {
            var out = ""
            var failure: Error?
            do {
                for try await delta in llm.stream(text, history: history, systemPrompt: systemPrompt) {
                    out += delta
                    if let capped = truncateIfOverLimit(out) { out = capped; setReply(replyID, out); break }
                    setReply(replyID, out)
                }
            } catch is CancellationError {
                // Stopped by the user — keep whatever streamed so far.
            } catch { failure = error }

            let final = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if final.isEmpty {
                let msg = failure?.localizedDescription ?? "Sorry, I didn't get a response — please try again."
                replace(replyID) { $0.content = msg; $0.isError = true }
            } else {
                // Output-side guardrail.
                let v = ChatGuardrail.evaluate(final)
                replace(replyID) { $0.content = v.map(ChatGuardrail.fallbackMessage) ?? final }
            }
            isGenerating = false; streamTask = nil
            save()
        }
    }

    func stop() { streamTask?.cancel() }

    func save() { historyStore.saveActiveSession(messages) }

    /// Clears the chat immediately; summarising and extracting profile items runs in the background.
    func endSession() {
        guard !messages.isEmpty, !isGenerating else { return }
        let snapshot = messages
        historyStore.clearActiveSession()
        messages = []

        Task {
            let r = await llm.processEndOfSession(snapshot)
            historyStore.append(ConversationSummary(
                summary: r.summary, newTraitsExtracted: r.traits, newInterestsExtracted: r.interests,
                newValuesExtracted: r.values, newGoalsExtracted: r.goals, messageCount: snapshot.count, messages: snapshot))
            profileStore.mergeExtractedTraits(r.traits)
            r.interests.forEach { profileStore.addItem(.interests, $0) }
            r.values.forEach { profileStore.addItem(.values, $0) }
            r.goals.forEach { profileStore.addItem(.goals, $0) }

            let total = r.traits.count + r.interests.count + r.values.count + r.goals.count
            notice = total > 0 ? "\(total) item\(total == 1 ? "" : "s") added to your profile" : "Session saved"
        }
    }

    // MARK: helpers

    private func setReply(_ id: String, _ content: String) { replace(id) { $0.content = content } }

    private func replace(_ id: String, _ transform: (inout ChatMessage) -> Void) {
        if let i = messages.lastIndex(where: { $0.id == id }) { transform(&messages[i]) }
    }

    /// `text` cut to `maxResponseWords` words plus "…", or nil if within the limit.
    private func truncateIfOverLimit(_ text: String) -> String? {
        var count = 0, idx = text.startIndex, end = text.startIndex
        var inWord = false
        while idx < text.endIndex {
            let ws = text[idx].isWhitespace
            if !ws && !inWord { count += 1; inWord = true }
            if ws { inWord = false }
            if count > maxResponseWords { return String(text[..<end]) + "…" }
            if !ws { end = text.index(after: idx) }
            idx = text.index(after: idx)
        }
        return nil
    }
}
