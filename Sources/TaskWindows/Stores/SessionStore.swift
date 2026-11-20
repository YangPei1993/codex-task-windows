import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private let reader = FeedReader(directory: SessionStore.codexDirectory)
    private(set) var sessions: [Session] = []
    private(set) var messages: [String: [SessionMessage]] = [:]
    private(set) var activities: [String: [TurnActivity]] = [:]
    private(set) var watching: Set<String> = []
    private(set) var pinned: Set<String> = []
    private(set) var lastRefresh: Date?
    private(set) var error: String?
    private(set) var refreshing = false
    private var drafts: [String: SessionDraft] = [:]
    // 启动时为恢复窗口预先加入监看、但尚未真正开窗的会话。
    private var preloaded: Set<String> = []
    private static let draftsKey = "unsentDrafts"
    private static let draftLimit = 50

    nonisolated static var codexDirectory: URL {
        if let directory = ProcessInfo.processInfo.environment["CODEX_HOME"], !directory.isEmpty {
            return URL(fileURLWithPath: directory, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    func preloadWatching(_ ids: [String]) {
        preloaded = Set(ids)
        watching.formUnion(ids)
    }

    /// 恢复完成后，移除未能重新开窗的预加载会话。
    func releasePreloaded() {
        for id in preloaded { stopWatching(id) }
        preloaded.removeAll()
    }

    func startWatching(_ id: String) {
        preloaded.remove(id)
        watching.insert(id)
        requestRefresh()
    }

    func stopWatching(_ id: String) {
        watching.remove(id)
        pinned.remove(id)
        messages[id] = nil
        activities[id] = nil
    }

    func setPinned(_ id: String, _ enabled: Bool) {
        if enabled { pinned.insert(id) } else { pinned.remove(id) }
    }

    func draft(for id: String) -> SessionDraft {
        if let existing = drafts[id] { return existing }
        let draft = SessionDraft()
        // 恢复上次退出时未发送的草稿。
        draft.text = savedDrafts[id] ?? ""
        drafts[id] = draft
        return draft
    }

    private var savedDrafts: [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.draftsKey) as? [String: String] ?? [:]
    }

    /// 退出时保存未发送草稿；尚未打开过的会话沿用之前保存的内容。
    func persistDrafts() {
        var saved = savedDrafts
        for (id, draft) in drafts {
            let text = draft.text
            saved[id] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
        if saved.count > Self.draftLimit {
            saved = Dictionary(uniqueKeysWithValues: saved.prefix(Self.draftLimit).map { ($0.key, $0.value) })
        }
        UserDefaults.standard.set(saved, forKey: Self.draftsKey)
    }

    func requestRefresh() {
        Task { await refresh() }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let snapshot = try await reader.fetch(watching: watching)
            sessions = snapshot.sessions
            messages = snapshot.messages.filter { watching.contains($0.key) }
            activities = snapshot.activities.filter { watching.contains($0.key) }
            for (id, items) in messages {
                drafts[id]?.observe(items)
            }
            lastRefresh = .now
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
