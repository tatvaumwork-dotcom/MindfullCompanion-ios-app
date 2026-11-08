import Foundation

/// Real star and constellation data (J2000 RA/Dec in degrees) from the d3-celestial project:
/// stars.tsv (~5,000 naked-eye stars: ra, dec, magnitude, B-V) and constellations.tsv (89 IAU figures).
struct SkyCatalog: Sendable {
    let stars: [Star]
    let constellations: [Constellation]

    struct Star: Sendable {
        let raDeg: Double
        let decDeg: Double
        let magnitude: Float
        let colorIndex: Float
    }

    struct Constellation: Sendable {
        let id: String
        let name: String
        let labelRa: Double
        let labelDec: Double
        /// Polylines of (raDeg, decDeg) points.
        let lines: [[(Double, Double)]]

        /// The 12 zodiac constellations, drawn more prominently.
        var isZodiac: Bool { SkyCatalog.zodiac.contains(id) }
    }

    private static let zodiac: Set<String> = ["Ari", "Tau", "Gem", "Cnc", "Leo", "Vir", "Lib", "Sco", "Sgr", "Cap", "Aqr", "Psc"]

    static func load(bundle: Bundle = .main) -> SkyCatalog {
        func lines(_ name: String) -> [[Substring]] {
            guard let url = bundle.url(forResource: name, withExtension: "tsv"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(whereSeparator: \.isNewline)
                .map { $0.split(separator: "\t", omittingEmptySubsequences: false) }
        }
        let stars = lines("stars").compactMap { p -> Star? in
            guard p.count >= 4, let ra = Double(p[0]), let dec = Double(p[1]),
                  let mag = Float(p[2]), let bv = Float(p[3]) else { return nil }
            return Star(raDeg: ra, decDeg: dec, magnitude: mag, colorIndex: bv)
        }
        let constellations = lines("constellations").compactMap { p -> Constellation? in
            guard p.count >= 5, let ra = Double(p[2]), let dec = Double(p[3]) else { return nil }
            let polylines = p[4].split(separator: "|").map { poly in
                poly.split(separator: ";").compactMap { pt -> (Double, Double)? in
                    let c = pt.split(separator: ",")
                    guard c.count >= 2, let r = Double(c[0]), let d = Double(c[1]) else { return nil }
                    return (r, d)
                }
            }
            return Constellation(id: String(p[0]), name: String(p[1]), labelRa: ra, labelDec: dec, lines: polylines)
        }
        return SkyCatalog(stars: stars, constellations: constellations)
    }
}
