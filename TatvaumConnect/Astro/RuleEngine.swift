import Foundation

// Deterministic chart interpretation against the bundled rule trees
// (house_behaviour.json, planet_house_rules.json).

struct PlanetReportEntry: Sendable {
    let sign: String
    let houseNumber: Int
    let state: String
}

struct ExpandedHouseInfo: Sendable {
    let sign: String
    let number: Int
    let houseName: String
    let representation: [String]
    let strengths: [String]
    let challenges: [String]
    let lifeAreas: [String]
}

struct ExpandedPlanetInfo: Sendable {
    let house: ExpandedHouseInfo
    let stateType: String
    let behavior: [String]
}

final class RuleEngine: @unchecked Sendable {  // immutable after init

    struct Prediction: Sendable {
        let traits: [String]
        let interests: [String]
        let values: [String]
        let goals: [String]
        let summary: String
    }

    private let houseBehaviour: [String: Any]
    private let planetHouseRules: [String: Any]

    private let combustionLimits: [VedicPlanet: Double] = [
        .Moon: 12, .Mars: 17, .Mercury: 14, .Jupiter: 11, .Venus: 10, .Saturn: 15,
    ]

    init(bundle: Bundle = .main) {
        func load(_ name: String) -> [String: Any] {
            guard let data = AstroData.data(name, bundle: bundle),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return obj
        }
        houseBehaviour = load("house_behaviour")
        planetHouseRules = load("planet_house_rules")
    }

    func generatePlanetReport(_ chart: HoroscopeChart) -> [String: PlanetReportEntry] {
        guard let sun = chart.planets.first(where: { $0.position.planet == .Sun }) else { return [:] }
        let sunLon = sun.position.siderealLongitude
        var out: [String: PlanetReportEntry] = [:]
        for p in chart.planets {
            let planet = p.position.planet
            var state = "Normal"
            if p.position.isRetrograde {
                state = "Retrograde"
            } else if let limit = combustionLimits[planet] {
                let raw = abs(p.position.siderealLongitude - sunLon)
                if min(raw, 360 - raw) <= limit { state = "Combust" }
            }
            if p.isExalted { state = "Exalted" } else if p.isDebilitated { state = "Debilitated" }
            out[planet.label] = PlanetReportEntry(sign: p.position.sign.label, houseNumber: p.house, state: state)
        }
        return out
    }

    func parseTreeAndRules(_ report: [String: PlanetReportEntry]) -> [String: ExpandedPlanetInfo] {
        var out: [String: ExpandedPlanetInfo] = [:]
        for (planet, entry) in report {
            guard let h = houseBehaviour[String(entry.houseNumber)] as? [String: Any] else { continue }
            func strings(_ key: String) -> [String] { h[key] as? [String] ?? [] }
            let house = ExpandedHouseInfo(
                sign: entry.sign, number: entry.houseNumber, houseName: h["House Name"] as? String ?? "",
                representation: strings("Representation"), strengths: strings("Strengths"),
                challenges: strings("Challenges"), lifeAreas: strings("Life Areas"))
            let node = ((planetHouseRules[planet] as? [String: Any])?[entry.sign] as? [String: Any])?[entry.state]
            out[planet] = ExpandedPlanetInfo(house: house, stateType: entry.state, behavior: node.map(Self.leaves) ?? [])
        }
        return out
    }

    func flattenTraits(_ e: [String: ExpandedPlanetInfo]) -> [String] { e.keys.sorted().flatMap { e[$0]!.behavior } }
    func flattenInterests(_ e: [String: ExpandedPlanetInfo]) -> [String] { uniqueHouseValues(e) { $0.house.lifeAreas } }
    func flattenValues(_ e: [String: ExpandedPlanetInfo]) -> [String] { uniqueHouseValues(e) { $0.house.strengths } }
    func flattenGoals(_ e: [String: ExpandedPlanetInfo]) -> [String] { uniqueHouseValues(e) { $0.house.challenges } }

    func compactSummary(_ e: [String: ExpandedPlanetInfo]) -> String {
        e.keys.sorted().map { planet in
            let info = e[planet]!
            let behavior = info.behavior.prefix(3).joined(separator: "; ")
            let areas = info.house.lifeAreas.prefix(3).joined(separator: ", ")
            return "\(planet): House \(info.house.number) (\(info.house.sign)), \(info.stateType) — \(behavior). Life areas: \(areas)."
        }.joined(separator: "\n")
    }

    /// Everything the profile needs from a chart, in one call.
    func predict(_ chart: HoroscopeChart) -> Prediction {
        let expanded = parseTreeAndRules(generatePlanetReport(chart))
        return Prediction(traits: flattenTraits(expanded), interests: flattenInterests(expanded),
                          values: flattenValues(expanded), goals: flattenGoals(expanded),
                          summary: compactSummary(expanded))
    }

    private func uniqueHouseValues(_ e: [String: ExpandedPlanetInfo], field: (ExpandedPlanetInfo) -> [String]) -> [String] {
        var byHouse: [Int: ExpandedPlanetInfo] = [:]
        for v in e.values { byHouse[v.house.number] = v }
        var seen = Set<String>(), out: [String] = []
        for k in byHouse.keys.sorted() { for s in field(byHouse[k]!) where seen.insert(s).inserted { out.append(s) } }
        return out
    }

    private static func leaves(_ node: Any) -> [String] {
        switch node {
        case let o as [String: Any]: o.keys.sorted().flatMap { leaves(o[$0]!) }
        case let a as [Any]: a.flatMap(leaves)
        case let s as String: [s]
        case let n as NSNumber: [n.stringValue]
        default: []
        }
    }
}
