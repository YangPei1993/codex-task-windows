import SwiftUI

struct SessionComposer: View {
    @Bindable var draft: SessionDraft
    let submit: () -> Void

    private var hasText: Bool {
        !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerEditor(text: $draft.text, submit: send)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                status
                Spacer(minLength: 0)
                if hasText && !draft.sending {
                    Button {
                        draft.text = ""
                    } label: {
                        Text("清空")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清空当前草稿")
                }
                Button(action: send) {
                    HStack(spacing: 4) {
                        Group {
                            if draft.sending {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 13))
                            }
                        }
                        .frame(width: 14, height: 14)
                        Text(draft.sending ? "发送中" : "发送")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 36)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!draft.canSend)
                .help("发送消息到本会话（Enter 或 ⌘Enter）")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(hasText ? Color.teal.opacity(0.45) : Color.secondary.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var status: some View {
        if draft.text.utf8.count > CodexQueue.messageLimit {
            Label("超出 64 KB 上限", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        } else if let feedback = draft.feedback {
            switch feedback {
            case .queued:
                Label(feedback.label, systemImage: "clock.badge.checkmark")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .help("Codex 按会话队列处理。原会话尚未载入时，可点「回 Codex」。")
            case .received:
                Label(feedback.label, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.teal)
                    .font(.caption)
            case .failed:
                Label(feedback.label, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .lineLimit(2)
                    .help(feedback.label)
            }
        } else {
            Text("Enter 发送 · ⇧Enter 换行")
                .foregroundStyle(.tertiary)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private func send() {
        guard !ComposerEditor.isComposing else { return }
        submit()
    }
}
