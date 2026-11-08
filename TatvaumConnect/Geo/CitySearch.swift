import Foundation
import Observation
import os

/// A place someone can be born in: name, region, country, coordinates and IANA timezone.
struct City: Hashable {
    let name: String
    let region: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    let population: Int

    /// "Hyderabad, Telangana, India"
    var label: String {
        var out: [String] = []
        for s in [name, region, country] where !s.trimmingCharacters(in: .whitespaces).isEmpty && !out.contains(s) { out.append(s) }
        return out.joined(separator: ", ")
    }
}

/// Offline world-city search over GeoNames "cities15000" (CC BY 4.0). Nothing is sent anywhere.
/// cities.tsv is pre-sorted by population, so bigger places rank first.
@MainActor @Observable
final class CitySearch {
    private(set) var isReady = false
    @ObservationIgnored private var entries: [Entry] = []

    private struct Entry { let city: City; let key: String; let region: String; let country: String }

    /// Loads off the main thread; pass `tsv` text to use a custom dataset.
    init(tsv: String? = nil) {
        Task {
            let e = await Task.detached(priority: .userInitiated) { Self.load(tsv) }.value
            entries = e; isReady = true
        }
    }

    /// Best matches for what the person typed, e.g. "hyder", "springfield, illinois" or
    /// "paris france". Prefix matches beat substring matches; ties go to bigger places.
    func search(_ raw: String, limit: Int = 8) -> [City] {
        Self.search(entries, raw, limit: limit)
    }

    nonisolated private static func search(_ entries: [Entry], _ raw: String, limit: Int) -> [City] {
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map { normalize($0) }.filter { !$0.isEmpty }
        guard let name = parts.first, name.count >= 2 else { return [] }
        let qualifiers = parts.dropFirst()

        func qualifies(_ e: Entry) -> Bool { qualifiers.allSatisfy { e.region.hasPrefix($0) || e.country.hasPrefix($0) } }

        var prefix: [City] = [], contains: [City] = []
        for e in entries {                              // already sorted by population
            if prefix.count >= limit { break }
            if e.key.hasPrefix(name) { if qualifies(e) { prefix.append(e.city) } }
            else if contains.count < limit && e.key.contains(name) { if qualifies(e) { contains.append(e.city) } }
        }
        // "paris france" without a comma: treat the last word as a qualifier if nothing matched.
        if prefix.isEmpty && contains.isEmpty && name.contains(" ") && qualifiers.isEmpty {
            let words = name.split(separator: " ")
            return search(entries, words.dropLast().joined(separator: " ") + "," + words.last!, limit: limit)
        }
        var seen = Set<City>()
        return Array((prefix + contains).filter { seen.insert($0).inserted }.prefix(limit))
    }

    /// Lowercase, accents removed ("São Paulo" → "sao paulo"), trimmed.
    nonisolated static func normalize<S: StringProtocol>(_ s: S) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func load(_ tsv: String?) -> [Entry] {
        guard let text = tsv ?? Bundle.main.url(forResource: "cities", withExtension: "tsv")
            .flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) else {
            Logger(subsystem: "com.tatvaum.connect", category: "CitySearch").error("Failed to load cities")
            return []
        }
        var out: [Entry] = []
        out.reserveCapacity(30_000)
        for line in text.split(separator: "\n") {
            let p = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard p.count >= 8, let lat = Double(p[4]), let lon = Double(p[5]) else { continue }
            let city = City(name: String(p[0]), region: String(p[2]), country: String(p[3]), latitude: lat, longitude: lon,
                            timezone: String(p[6]), population: Int(p[7].trimmingCharacters(in: .whitespaces)) ?? 0)
            out.append(Entry(city: city, key: normalize(p[1].isEmpty || p[1].allSatisfy(\.isWhitespace) ? p[0] : p[1]),
                             region: normalize(city.region), country: normalize(city.country)))
        }
        return out
    }

    /// For tests: parse TSV text synchronously.
    nonisolated static func parse(_ tsv: String) -> [City] { load(tsv).map(\.city) }
    nonisolated static func searchSync(_ tsv: String, _ q: String, limit: Int = 8) -> [City] { search(load(tsv), q, limit: limit) }
}
