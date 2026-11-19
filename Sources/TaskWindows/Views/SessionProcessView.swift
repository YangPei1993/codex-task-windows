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
                HStack(spacing: 8) {
                    Image(systemName: event.kind.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.teal)
                        .frame(width: 20, height: 20)
                        .background(Color.teal.opacity(0.12), in: Circle())

                    Text(count == 1 ? event.kind.label : "\(event.kind.label) ×\(count)")
                        .fontWeight(.medium)
                        .foregroundStyle(.primary.opacity(0.85))

                    if let state = event.state {
                        let isWarning = (state == .failed || state == .declined)
                        let isDone = (state == .completed)
                        Text(state.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isWarning ? Color.orange : (isDone ? Color.teal : .secondary))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                (isWarning ? Color.orange : (isDone ? Color.teal : Color.secondary)).opacity(0.12),
                                in: Capsule()
                            )
                    }
                    Spacer(minLength: 4)
                    time(event.date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func textRow(_ title: String, icon: String, date: Date, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundStyle(.teal)
                    .font(.caption.weight(.semibold))
                Spacer()
                time(date)
            }
            MessageMarkdown(source: text).equatable().font(.system(size: 13))
        }
        .padding(11)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func time(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.hour().minute().second()))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
