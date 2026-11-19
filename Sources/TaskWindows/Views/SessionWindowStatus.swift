import SwiftUI

struct StatusBadge: View {
    let status: SessionStatus
    var animates = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: animates && !reduceMotion && status == .running)
                .accessibilityHidden(true)
            Text(status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(status.tint.opacity(0.27)))
        .help(status.explanation)
    }
}

struct SessionWindowStatus: View {
    let store: SessionStore
    let original: Session
    let openInCodex: () -> Void
    @State private var showingDetails = false

    private var session: Session { store.sessions.first { $0.id == original.id } ?? original }

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            StatusBadge(status: session.status, animates: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(width: 90, height: 24)
        .accessibilityLabel("会话状态：\(session.status.label)")
        .accessibilityHint("显示本轮状态详情")
        .help("查看本轮状态详情")
        .popover(isPresented: $showingDetails) {
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            StatusBadge(status: session.status)
            Text(session.status.explanation)
                .fixedSize(horizontal: false, vertical: true)
            if let activity = session.activity {
                LabeledContent("最近活动") {
                    Text(activity.formatted(.dateTime.hour().minute().second())).monospacedDigit()
                }
                if let action = session.lastAction {
                    Text(action).font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.error != nil {
                Label("本地状态同步暂不可用", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if session.status == .failed || session.status == .uncertain {
                Button("在 Codex 查看") {
                    showingDetails = false
                    openInCodex()
                }
                .buttonStyle(.link)
            }
        }
        .font(.subheadline)
        .padding(14)
        .frame(width: 246, alignment: .leading)
    }
}
