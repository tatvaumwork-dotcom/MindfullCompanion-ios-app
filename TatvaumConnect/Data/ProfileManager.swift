import Foundation
import Observation
import os

/// Which profiles exist (in order), which one is selected, and which one is the phone owner's ("Me").
struct ProfileIndex: Codable {
    var ids: [String] = []
    var activeId: String?
    var primaryId: String?
}

/// Everything that belongs to one person: their profile, chat summaries and the chat in progress.
@MainActor
final class ProfileSlot: Identifiable {
    let id: String
    let profileStore: ProfileStore
    let historyStore: HistoryStore
    let chat: ChatSession

    init(id: String, profileStore: ProfileStore, historyStore: HistoryStore, chat: ChatSession) {
        self.id = id; self.profileStore = profileStore; self.historyStore = historyStore; self.chat = chat
    }
}

/// Up to `max` profiles, each stored in its own folder (Documents/profiles/<id>/) with the same
/// profile.json / history.json / active_session.json the single-profile app used.
/// All mutation happens on the main actor.
@MainActor @Observable
final class ProfileManager {
    static let max = 5

    private(set) var ids: [String] = []
    private(set) var primaryId: String?
    private(set) var active: ProfileSlot!

    /// A profile being added that hasn't finished onboarding yet.
    private(set) var pendingNewId: String?
    @ObservationIgnored private var returnToId: String?

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let dir: URL
    @ObservationIgnored private let indexFile: JSONFile<ProfileIndex>
    @ObservationIgnored private let llm: LLMService
    @ObservationIgnored private let ruleEngine: RuleEngine
    @ObservationIgnored private var slots: [String: ProfileSlot] = [:]
    private static let log = Logger(subsystem: "com.tatvaum.connect", category: "ProfileManager")

    var all: [ProfileSlot] { ids.map(slot) }
    var canAdd: Bool { ids.count < Self.max }
    /// True while the selected profile is one being added (its onboarding can be cancelled).
    var isAddingActive: Bool { pendingNewId != nil && pendingNewId == active.id }

    init(root: URL = .documentsDirectory, llm: LLMService, ruleEngine: RuleEngine) {
        self.root = root
        self.llm = llm
        self.ruleEngine = ruleEngine
        dir = root.appending(path: "profiles")
        indexFile = JSONFile("profiles.json", in: root)
        active = load()
    }

    private func folder(_ id: String) -> URL { dir.appending(path: id, directoryHint: .isDirectory) }

    private func slot(_ id: String) -> ProfileSlot {
        if let s = slots[id] { return s }
        let d = folder(id)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let profileStore = ProfileStore(dir: d, llm: llm, ruleEngine: ruleEngine)
        let historyStore = HistoryStore(dir: d)
        let s = ProfileSlot(id: id, profileStore: profileStore, historyStore: historyStore,
                            chat: ChatSession(llm: llm, profileStore: profileStore, historyStore: historyStore))
        slots[id] = s
        return s
    }

    private func load() -> ProfileSlot {
        var index = indexFile.read() ?? migrateSingleProfile()
        // Drop profiles whose folder is gone, and unfinished additions left by an interrupted "Add a profile".
        let fm = FileManager.default
        let kept = index.ids.filter { id in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: folder(id).path, isDirectory: &isDir) && isDir.boolValue
                && (id == index.primaryId || slot(id).profileStore.profile.isOnboarded)
        }
        if kept.isEmpty { index = ProfileIndex() } else if kept != index.ids { index.ids = kept }
        if index.ids.isEmpty {
            let id = newID()
            index = ProfileIndex(ids: [id], activeId: id, primaryId: id)
        }
        let activeId = index.activeId.flatMap { index.ids.contains($0) ? $0 : nil } ?? index.ids[0]
        index.activeId = activeId
        index.primaryId = index.primaryId.flatMap { index.ids.contains($0) ? $0 : nil } ?? index.ids[0]
        ids = index.ids
        primaryId = index.primaryId
        indexFile.write(index)
        return slot(activeId)
    }

    /// First launch after the update: the existing single profile becomes profile #1 ("Me").
    private func migrateSingleProfile() -> ProfileIndex {
        let id = newID()
        let target = folder(id)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["profile.json", "history.json", "active_session.json"] {
            let old = root.appending(path: name)
            guard FileManager.default.fileExists(atPath: old.path) else { continue }
            do { try FileManager.default.moveItem(at: old, to: target.appending(path: name)) }
            catch { Self.log.warning("Could not move \(name): \(error)") }
        }
        return ProfileIndex(ids: [id], activeId: id, primaryId: id)
    }

    private func saveIndex() {
        let snapshot = ProfileIndex(ids: ids, activeId: active.id, primaryId: primaryId), f = indexFile
        writerQueue.async { f.write(snapshot) }
    }

    func switchTo(_ id: String) {
        guard id != active.id, ids.contains(id) else { return }
        active.chat.save()
        active = slot(id)
        saveIndex()
    }

    /// Starts a new, empty profile and selects it; the app then shows onboarding for it.
    func addProfile() {
        guard canAdd else { return }
        let id = newID()
        returnToId = active.id
        active.chat.save()
        ids.append(id)
        pendingNewId = id
        active = slot(id)
        saveIndex()
    }

    /// Called once the new profile's birth details are saved.
    func finishAdding() {
        pendingNewId = nil
        returnToId = nil
    }

    /// Backs out of "Add a profile": removes the unfinished profile and returns to the previous one.
    func cancelAdding() {
        guard let id = pendingNewId else { return }
        let back = returnToId
        pendingNewId = nil
        returnToId = nil
        delete(id, switchTo: back)
    }

    /// Deletes a profile and everything stored for it. "Me" and the last remaining profile can't be deleted.
    func delete(_ id: String, switchTo target: String? = nil) {
        guard id != primaryId, ids.count > 1, ids.contains(id) else { return }
        slots[id]?.chat.stop()
        ids.removeAll { $0 == id }
        if active.id == id {
            let next = [target, primaryId].compactMap { $0 }.first(where: ids.contains) ?? ids[0]
            active = slot(next)
        }
        slots[id] = nil
        saveIndex()
        let f = folder(id)
        writerQueue.async { try? FileManager.default.removeItem(at: f) }
    }
}
