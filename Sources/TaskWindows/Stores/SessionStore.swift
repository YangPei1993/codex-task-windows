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

    nonisolated static var codexDirectory: URL {
        if let directory = ProcessInfo.processInfo.environment["CODEX_HOME"], !directory.isEmpty {
            return URL(fileURLWithPath: directory, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    func startWatching(_ id: String) {
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
        drafts[id] = draft
        return draft
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
