import Foundation
import Observation

/// App-wide singletons. State objects are mutated on the main actor only.
@MainActor @Observable
final class AppContainer {
    let llm = LLMService()
    let profileStore: ProfileStore
    let historyStore = HistoryStore()
    let chat: ChatSession
    let thirdEye = ThirdEyeStore()
    let cities = CitySearch()
    let pincodes = PincodeGeoService()
    /// Tab requested from outside the app (e.g. tapping the weekly Third Eye notification).
    var requestedTab: String?
    @ObservationIgnored lazy var skyCatalog: SkyCatalog = SkyCatalog.load()

    init() {
        profileStore = ProfileStore(llm: llm, ruleEngine: RuleEngine())
        chat = ChatSession(llm: llm, profileStore: profileStore, historyStore: historyStore)
    }
}
