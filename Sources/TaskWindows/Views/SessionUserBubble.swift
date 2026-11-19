import SwiftUI

struct SessionUserBubble: View {
    let text: String
    let date: Date
    var title = "你的消息"
    var status: String?
    @State private var expanded = false

    private var longMessage: Bool {
        text.utf8.count > 300 || text.split(separator: "\n", omittingEmptySubsequences: false).count > 6
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 28)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.teal)
                    Text(title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(Session.friendlyTimestamp(date))
                        .monospacedDigit()
                    if let status {
                        Text(status)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(.teal.opacity(0.16), in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(verbatim: text)
                    .font(.system(size: 13))
                    .lineSpacing(3.5)
                    .lineLimit(longMessage && !expanded ? 6 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if longMessage {
                    Button {
                        expanded.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(expanded ? "收起内容" : "展开全文")
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.teal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                LinearGradient(
                    colors: [.teal.opacity(0.16), .teal.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.teal.opacity(0.26), lineWidth: 1)
            )
        }
    }
}
