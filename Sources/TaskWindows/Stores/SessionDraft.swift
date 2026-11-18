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
    private(set) var outbox = SessionOutbox()
    private var lastSubmittedID: UUID?

    var canSend: Bool {
        !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.contains("\0") && text.utf8.count <= CodexQueue.messageLimit
    }

    func send(to session: Session, previous: [SessionMessage], refresh: @escaping () -> Void) {
        guard canSend, session.acceptsMessages else { return }
        let submitted = text
        let id = outbox.submit(submitted, at: .now, knownMessages: previous)
        lastSubmittedID = id
        sending = true
        feedback = nil
        Task {
            defer { sending = false }
            do {
                try await CodexQueue.submit(submitted, to: session)
                feedback = outbox.markQueued(id) ? .queued : .received
                if text == submitted { text = "" }
                refresh()
            } catch {
                if outbox.remove(id) {
                    feedback = .failed(error.localizedDescription)
                } else {
                    feedback = .received
                    if text == submitted { text = "" }
                }
            }
        }
    }

    func observe(_ messages: [SessionMessage]) {
        guard !outbox.messages.isEmpty else { return }
        let delivered = outbox.reconcile(messages)
        if let lastSubmittedID, delivered.contains(lastSubmittedID) {
            feedback = .received
        }
    }
}
