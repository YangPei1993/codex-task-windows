import SwiftUI

struct SessionView: View {
    let store: SessionStore
    let original: Session
    @Bindable var draft: SessionDraft
    let pin: () -> Void
    let openInCodex: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var session: Session { store.sessions.first { $0.id == original.id } ?? original }
    private var items: [SessionMessage] { store.messages[original.id] ?? [] }
    private var activities: [TurnActivity] { store.activities[original.id] ?? [] }
    private var pinned: Bool { store.pinned.contains(original.id) }
    @State private var breathing = false

    private var isBreathing: Bool {
        !reduceMotion && session.status == .running
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.status != .unknown {
                session.status.tint
                    .opacity(isBreathing ? (breathing ? 1.0 : 0.4) : 0.9)
                    .frame(height: 3.5)
                    .shadow(color: isBreathing ? session.status.tint.opacity(breathing ? 0.65 : 0.1) : .clear, radius: 5, y: 1)
                    .accessibilityHidden(true)
            }
            header
            Divider().opacity(0.6)
            if let error = store.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("本地同步暂缓 · \(error)")
                        .lineLimit(2)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.orange.opacity(0.08))
            }
            if items.isEmpty && activities.isEmpty && draft.outbox.messages.isEmpty {
                emptyTranscript
            } else {
                SessionTranscript(items: items, activities: activities, outgoing: draft.outbox.messages,
                                  turnID: session.currentTurnID,
                                  running: session.status == .running)
            }
            Divider().opacity(0.6)
            composer
        }
        .frame(minWidth: 320, minHeight: 280)
        .tint(.teal)
        .onAppear { updateBreathing() }
        .onChange(of: isBreathing) { updateBreathing() }
    }

    private func updateBreathing() {
        if isBreathing {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.24)) {
                breathing = false
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Label(session.project, systemImage: "folder")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(.secondary.opacity(0.1), in: Capsule())

                Spacer(minLength: 4)

                Button(action: pin) {
                    HStack(spacing: 4) {
                        Image(systemName: pinned ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .semibold))
                        if pinned {
                            Text("已置顶").font(.caption2.weight(.semibold))
                        }
                    }
                    .foregroundStyle(pinned ? .teal : .secondary)
                    .padding(.horizontal, pinned ? 8 : 6)
                    .padding(.vertical, 4)
                    .background(pinned ? Color.teal.opacity(0.14) : Color.secondary.opacity(0.08), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(pinned ? Color.teal.opacity(0.3) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(pinned ? "取消窗口置顶" : "将窗口置顶在最前方")
                .accessibilityLabel(pinned ? "取消置顶" : "置顶窗口")

                Button(action: openInCodex) {
                    Label("回 Codex", systemImage: "arrow.up.right")
                        .font(.caption.weight(.medium))
                }
                .controlSize(.small)
                .help("在原 Codex 桌面端打开此会话，可处理审批或终止任务")
            }

            Text(verbatim: session.title)
                .font(.system(size: 16.5, weight: .semibold))
                .lineLimit(2)
                .help(session.title)

            if let activity = session.activity, let action = session.lastAction {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(session.status == .running ? session.status.tint : .secondary)
                        .symbolEffect(.pulse, options: .repeating, isActive: isBreathing)
                    Text("\(action) · \(Session.friendlyTimestamp(activity))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background {
            if session.status != .unknown {
                LinearGradient(
                    colors: [
                        session.status.tint.opacity(isBreathing ? (breathing ? 0.25 : 0.09) : 0.16),
                        session.status.tint.opacity(isBreathing ? (breathing ? 0.06 : 0.015) : 0.03)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: session.status)
    }

    private var emptyTranscript: some View {
        Group {
            if store.messages[original.id] == nil, store.error == nil {
                ProgressView("正在读取会话消息…")
            } else {
                ContentUnavailableView("暂无对话消息", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("当 Codex 产生回复或活动后将自动显示在这里。"))
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
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("此会话为只读监看，如需回复请前往原窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("去回复", action: openInCodex)
                    .controlSize(.small)
                    .buttonStyle(.link)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(.secondary.opacity(0.04))
        }
    }

}
