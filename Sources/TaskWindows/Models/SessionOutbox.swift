import Foundation

struct OutgoingMessage: Identifiable {
    enum Phase {
        case sending, queued

        var label: String { self == .sending ? "发送中" : "已排队" }
    }

    let id = UUID()
    let text: String
    let date: Date
    fileprivate let previousIDs: Set<String>
    fileprivate(set) var phase = Phase.sending
}

struct SessionOutbox {
    private(set) var messages: [OutgoingMessage] = []
    private var matchedIDs: Set<String> = []

    mutating func submit(_ text: String, at date: Date, knownMessages: [SessionMessage]) -> UUID {
        let new = OutgoingMessage(text: text, date: date,
                                  previousIDs: Set(knownMessages.filter { $0.kind == .userMessage }.map(\.id)))
        messages.append(new)
        return new.id
    }

    mutating func markQueued(_ id: UUID) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return false }
        messages[index].phase = .queued
        return true
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return false }
        messages.remove(at: index)
        if messages.isEmpty { matchedIDs.removeAll() }
        return true
    }

    mutating func reconcile(_ records: [SessionMessage]) -> Set<UUID> {
        var delivered: Set<UUID> = []
        guard !messages.isEmpty else { return delivered }
        for record in records where record.kind == .userMessage && !matchedIDs.contains(record.id) {
            guard let index = messages.firstIndex(where: { item in
                let since = floor(item.date.timeIntervalSince1970 * 1000) / 1000
                return record.date.timeIntervalSince1970 >= since
                    && !item.previousIDs.contains(record.id)
                    && item.text.trimmingCharacters(in: .whitespacesAndNewlines) == record.text
            }) else { continue }
            matchedIDs.insert(record.id)
            delivered.insert(messages.remove(at: index).id)
        }
        if messages.isEmpty { matchedIDs.removeAll() }
        return delivered
    }
}
