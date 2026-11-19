import SwiftUI

enum ProcessEntry: Identifiable {
    case message(SessionMessage)
    case activity(TurnActivity, count: Int)

    var id: String {
        switch self {
        case .message(let message): "process-message-\(message.id)"
        case .activity(let event, _): "activity-\(event.id)"
        }
    }

    var date: Date {
        switch self {
        case .message(let message): message.date
        case .activity(let event, _): event.date
        }
    }

    static func timeline(messages: [SessionMessage], activities: [TurnActivity]) -> [Self] {
        let events = messages.map(Self.message) + activities.map { .activity($0, count: 1) }
        let sorted = events.sorted { left, right in
            left.date == right.date ? left.id < right.id : left.date < right.date
        }
        var timeline: [Self] = []
        for event in sorted {
            if case .activity(let current, _) = event,
               case .activity(let previous, let count) = timeline.last,
               current.text == nil, previous.text == nil,
               current.kind == previous.kind, current.state == previous.state {
                timeline[timeline.count - 1] = .activity(current, count: count + 1)
            } else {
                timeline.append(event)
            }
        }
        return timeline
    }
}

struct SessionProcessRow: View {
    let entry: ProcessEntry
    var isLatest = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        switch entry {
        case .message(let message):
            if message.kind == .userMessage {
                SessionUserBubble(text: message.text, date: message.date, title: message.questionLabel)
            } else {
                textRow("进度", icon: "text.bubble", date: message.date, text: message.text)
            }
        case .activity(let event, let count):
            if let text = event.text {
                textRow(event.kind.label, icon: event.kind.icon, date: event.date, text: text)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: event.kind.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.teal)
                        .frame(width: 20, height: 20)
                        .background(Color.teal.opacity(0.12), in: Circle())

                    Text(count == 1 ? event.kind.label : "\(event.kind.label) ×\(count)")
                        .fontWeight(.medium)
                        .foregroundStyle(.primary.opacity(0.88))

                    if let state = event.state {
                        let isWarning = (state == .failed || state == .declined)
                        let isRunning = (state == .inProgress)
                        let isDone = (state == .completed)
                        let tint: Color = isWarning ? .orange : (isRunning ? .blue : (isDone ? .teal : .secondary))
                        HStack(spacing: 3) {
                            if isRunning {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                                    .accessibilityHidden(true)
                            }
                            Text(state.label)
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(tint.opacity(0.13), in: Capsule())
                        .overlay(Capsule().strokeBorder(tint.opacity(0.24), lineWidth: 1))
                    }
                    Spacer(minLength: 4)
                    time(event.date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.11), lineWidth: 1)
                )
            }
        }
    }

    private func isLongText(_ text: String) -> Bool {
        !isLatest && (text.count > 130 || text.split(separator: "\n", omittingEmptySubsequences: false).count > 3)
    }

    private func summaryLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " ")
    }

    private func textRow(_ title: String, icon: String, date: Date, text: String) -> some View {
        let shouldCollapse = isLongText(text) && !expanded
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon)
                    .foregroundStyle(.teal)
                    .font(.caption.weight(.semibold))
                Spacer()
                if isLongText(text) {
                    Button(expanded ? "收起" : "展开") {
                        expanded.toggle()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.teal.opacity(0.1), in: Capsule())
                    .buttonStyle(.plain)
                }
                time(date)
            }
            if shouldCollapse {
                Text(verbatim: summaryLine(text))
                    .font(.system(size: 12.5))
                    .lineSpacing(4)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { expanded = true }
            } else {
                MessageMarkdown(source: text).equatable().font(.system(size: 13))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.secondary.opacity(isLatest ? 0.065 : 0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isLatest ? Color.teal.opacity(0.24) : Color.secondary.opacity(0.13), lineWidth: 1)
        )
    }

    private func time(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.hour().minute().second()))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
