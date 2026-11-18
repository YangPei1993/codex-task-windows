import Foundation
import Observation

@MainActor
@Observable
final class SessionDraft {
    enum Feedback {
        case queued, received, failed(String)

        var label: String {
            switch self {
            case .queued: "已加入 Codex 队列"
            case .received: "已进入原会话"
            case .failed(let message): message
            }
        }
    }

    var text = ""
    private(set) var sending = false
    private(set) var feedback: Feedback?
    private var latest: Pending?

    private struct Pending {
        let text: String
        let submittedAt: Date
        let previousIDs: Set<String>
    }

    var canSend: Bool {
        !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.contains("\0") && text.utf8.count <= CodexQueue.messageLimit
    }

    func send(to session: Session, previous: [SessionMessage], refresh: @escaping () -> Void) {
        guard canSend, session.acceptsMessages else { return }
        let submitted = text
        let pending = Pending(text: submitted.trimmingCharacters(in: .whitespacesAndNewlines),
                              submittedAt: .now, previousIDs: Set(previous.map(\.id)))
        sending = true
        feedback = nil
        Task {
            defer { sending = false }
            do {
                try await CodexQueue.submit(submitted, to: session)
                latest = pending
                feedback = .queued
                if text == submitted { text = "" }
                refresh()
            } catch {
                feedback = .failed(error.localizedDescription)
            }
        }
    }

    func observe(_ messages: [SessionMessage]) {
        guard let latest, case .queued = feedback else { return }
        if messages.contains(where: {
            $0.kind == .userMessage && $0.date >= latest.submittedAt
                && !latest.previousIDs.contains($0.id) && $0.text == latest.text
        }) {
            feedback = .received
            self.latest = nil
        }
    }
}
