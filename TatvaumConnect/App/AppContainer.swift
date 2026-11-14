import Foundation
import Observation

/// App-wide singletons. State objects are mutated on the main actor only.
@MainActor @Observable
final class AppContainer {
    let llm = LLMService()
    /// Up to 5 profiles; the stores below always belong to the selected one (views refresh on switch).
    let profiles: ProfileManager
    let thirdEye = ThirdEyeStore()
    let cities = CitySearch()
    let pincodes = PincodeGeoService()
    @ObservationIgnored lazy var skyCatalog: SkyCatalog = SkyCatalog.load()

    var profileStore: ProfileStore { profiles.active.profileStore }
    var historyStore: HistoryStore { profiles.active.historyStore }
    var chat: ChatSession { profiles.active.chat }

    init() {
        profiles = ProfileManager(llm: llm, ruleEngine: RuleEngine())
    }
}
