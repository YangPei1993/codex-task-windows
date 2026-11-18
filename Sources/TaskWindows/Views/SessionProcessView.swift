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
                HStack(spacing: 6) {
                    Label(count == 1 ? event.kind.label : "\(event.kind.label) ×\(count)",
                          systemImage: event.kind.icon)
                    if let state = event.state {
                        Text(state.label)
                            .foregroundStyle(state == .failed || state == .declined ? Color.orange : .secondary)
                    }
                    Spacer(minLength: 4)
                    time(event.date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
            }
        }
    }

    private func textRow(_ title: String, icon: String, date: Date, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(.teal)
                Spacer()
                time(date)
            }
            .font(.caption.weight(.medium))
            MessageMarkdown(source: text).equatable().font(.system(size: 13))
        }
        .padding(10)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func time(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.hour().minute().second()))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
