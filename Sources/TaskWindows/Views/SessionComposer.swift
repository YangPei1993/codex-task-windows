import SwiftUI

struct SessionComposer: View {
    @Bindable var draft: SessionDraft
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerEditor(text: $draft.text, submit: send)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                status
                Spacer(minLength: 0)
                Button(action: send) {
                    Label(draft.sending ? "发送中" : "发送", systemImage: "arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSend)
                .help("发送到本会话（Enter 或 ⌘Enter）")
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 7)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.25)))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var status: some View {
        if draft.text.utf8.count > CodexQueue.messageLimit {
            Text("单条消息最多 64 KB").foregroundStyle(.orange).font(.caption)
        } else if let feedback = draft.feedback {
            switch feedback {
            case .queued:
                Label(feedback.label, systemImage: "clock").foregroundStyle(.secondary).font(.caption)
                    .help("Codex 按会话队列处理。原会话尚未载入时，可点「回 Codex」。")
            case .received:
                Label(feedback.label, systemImage: "checkmark.circle").foregroundStyle(.teal).font(.caption)
            case .failed:
                Label(feedback.label, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange).font(.caption).lineLimit(2).help(feedback.label)
            }
        } else {
            Text("Enter 发送 · ⇧Enter 换行").foregroundStyle(.secondary).font(.caption)
                .lineLimit(1)
        }
    }

    private func send() {
        guard !ComposerEditor.isComposing else { return }
        submit()
    }
}
