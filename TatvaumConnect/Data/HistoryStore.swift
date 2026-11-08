import Foundation
import Observation

/// Completed session summaries (newest first) plus the in-progress session.
@MainActor @Observable
final class HistoryStore {
    private(set) var summaries: [ConversationSummary]
    /// Messages of the unfinished session, restored at launch.
    @ObservationIgnored let restoredActiveMessages: [ChatMessage]

    @ObservationIgnored private let summariesFile = JSONFile<[ConversationSummary]>("history.json")
    @ObservationIgnored private let activeFile = JSONFile<[ChatMessage]>("active_session.json")

    init() {
        summaries = summariesFile.read() ?? []
        restoredActiveMessages = activeFile.read() ?? []
    }

    func append(_ s: ConversationSummary) {
        summaries.insert(s, at: 0)
        let snapshot = summaries, f = summariesFile
        writerQueue.async { f.write(snapshot) }
    }

    func saveActiveSession(_ messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }
        let f = activeFile
        writerQueue.async { f.write(messages) }
    }

    func clearActiveSession() {
        let f = activeFile
        writerQueue.async { f.delete() }
    }
}
