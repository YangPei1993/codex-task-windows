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
            Spacer(minLength: 26)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(title).fontWeight(.semibold).foregroundStyle(.primary)
                    Text(date.formatted(.dateTime.hour().minute())).monospacedDigit()
                    if let status { Text(status) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(verbatim: text)
                    .font(.system(size: 13))
                    .lineLimit(longMessage && !expanded ? 6 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if longMessage {
                    Button(expanded ? "收起" : "展开全文") { expanded.toggle() }
                        .font(.caption)
                        .buttonStyle(.link)
                }
            }
            .padding(11)
            .background(.teal.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
