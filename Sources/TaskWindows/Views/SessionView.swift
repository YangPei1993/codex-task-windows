import SwiftUI

struct SessionView: View {
    let store: SessionStore
    let original: Session
    @Bindable var draft: SessionDraft
    let pin: () -> Void
    let openInCodex: () -> Void

    private var session: Session { store.sessions.first { $0.id == original.id } ?? original }
    private var items: [SessionMessage] { store.messages[original.id] ?? [] }
    private var activities: [TurnActivity] { store.activities[original.id] ?? [] }
    private var pinned: Bool { store.pinned.contains(original.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = store.error {
                Label("同步失败 · \(error)", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .padding(8)
            }
            if items.isEmpty && activities.isEmpty && draft.outbox.messages.isEmpty {
                emptyTranscript
            } else {
                SessionTranscript(items: items, activities: activities, outgoing: draft.outbox.messages,
                                  turnID: session.currentTurnID,
                                  running: session.status == .running)
            }
            Divider()
            composer
        }
        .frame(minWidth: 310, minHeight: 280)
        .tint(.teal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(verbatim: session.project)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusBadge(status: session.status)
                Button(action: pin) {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .foregroundStyle(pinned ? .teal : .secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(pinned ? "取消置顶" : "置顶窗口")
                .accessibilityLabel(pinned ? "取消置顶" : "置顶窗口")
                Button(action: openInCodex) {
                    Label("回 Codex", systemImage: "arrow.up.right")
                        .font(.caption.weight(.medium))
                }
                .controlSize(.small)
                .help("打开原会话，可继续发消息和处理审批")
            }
            Text(verbatim: session.title)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(2)
                .help(session.title)
            if let activity = session.activity, let action = session.lastAction {
                Label("\(action) · \(activity.formatted(.dateTime.hour().minute().second()))", systemImage: "waveform.path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }

    private var emptyTranscript: some View {
        Group {
            if store.messages[original.id] == nil, store.error == nil {
                ProgressView("正在读取消息")
            } else {
                Text("暂无消息").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var composer: some View {
        if session.acceptsMessages {
            SessionComposer(draft: draft) {
                draft.send(to: session, previous: items, refresh: store.requestRefresh)
            }
        } else {
            Text("此会话可在原 Codex 窗口中回复。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
        }
    }

}
