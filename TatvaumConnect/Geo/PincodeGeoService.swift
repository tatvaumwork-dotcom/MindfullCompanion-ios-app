import Foundation
import Observation
import os

struct PincodePlace: Equatable { let name: String; let latitude: Double; let longitude: Double }

/// Indian PIN code → coordinates, from the bundled `pincodes.tsv` (pin, name, lat, lon).
@MainActor @Observable
final class PincodeGeoService {
    private(set) var isReady = false
    @ObservationIgnored private var byPincode: [Int: PincodePlace] = [:]
    @ObservationIgnored private var sortedPins: [Int] = []

    init(tsv: String? = nil) {
        Task {
            let r = await Task.detached(priority: .userInitiated) { Self.load(tsv) }.value
            byPincode = r.0; sortedPins = r.1; isReady = true
        }
    }

    /// First coordinate for the PIN, or the numerically nearest known PIN if it isn't in the dataset.
    func resolve(_ rawPincode: String) -> PincodePlace? {
        let digits = rawPincode.filter(\.isASCII).filter(\.isNumber)
        guard digits.count == 6, let pin = Int(digits) else { return nil }
        if let p = byPincode[pin] { return p }
        // Indian PINs are assigned regionally, so numerically close codes are usually close places.
        var lo = 0, hi = sortedPins.count
        while lo < hi { let m = (lo + hi) / 2; if sortedPins[m] < pin { lo = m + 1 } else { hi = m } }
        let near = [lo - 1, lo].filter { sortedPins.indices.contains($0) }.map { sortedPins[$0] }
        return near.min { abs($0 - pin) < abs($1 - pin) }.flatMap { byPincode[$0] }
    }

    nonisolated static func load(_ tsv: String? = nil) -> ([Int: PincodePlace], [Int]) {
        guard let text = tsv ?? Bundle.main.url(forResource: "pincodes", withExtension: "tsv")
            .flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) else {
            Logger(subsystem: "com.tatvaum.connect", category: "PincodeGeoService").error("Failed to load pincodes")
            return ([:], [])
        }
        var map = [Int: PincodePlace](minimumCapacity: 20_000)
        for line in text.split(separator: "\n") {
            let p = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard p.count == 4, let pin = Int(p[0]), let lat = Double(p[2]), let lon = Double(p[3].trimmingCharacters(in: .whitespaces)) else { continue }
            map[pin] = PincodePlace(name: String(p[1]), latitude: lat, longitude: lon)
        }
        return (map, map.keys.sorted())
    }
}
