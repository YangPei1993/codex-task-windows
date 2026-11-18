import SwiftUI

struct SessionTranscript: View {
    private enum Scope: String, CaseIterable {
        case latest = "对话"
        case process = "过程"
        case history = "全部消息"
    }

    let items: [SessionMessage]
    let activities: [TurnActivity]
    let outgoing: [OutgoingMessage]
    let turnID: String?
    let running: Bool
    @State private var scope: Scope
    @State private var followsLatest = true
    @State private var priorExpanded = false

    init(items: [SessionMessage], activities: [TurnActivity], outgoing: [OutgoingMessage],
         turnID: String?, running: Bool) {
        self.items = items
        self.activities = activities
        self.outgoing = outgoing
        self.turnID = turnID
        self.running = running
        _scope = State(initialValue: running ? .process : .latest)
    }

    private var currentTurn: [SessionMessage] { items.filter { $0.turnID == (turnID ?? items.last?.turnID) } }
    private var result: SessionMessage? { currentTurn.last { $0.kind == .result } }
    private var progress: [SessionMessage] { currentTurn.filter { $0.kind == .progress } }
    private var contextualQuestion: SessionMessage? {
        currentTurn.contains { $0.kind == .userMessage } ? nil : items.last { $0.questionContext != nil }
    }
    private var process: [ProcessEntry] {
        let context = contextualQuestion.map { [$0] } ?? []
        return ProcessEntry.timeline(messages: context + currentTurn.filter { $0.kind != .result },
                                     activities: activities)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("消息范围", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                if scope != .latest {
                    Toggle("跟随最新", isOn: $followsLatest).toggleStyle(.checkbox)
                }
            }
            .font(.caption)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            Divider()
            ScrollViewReader { scroll in
                if scope == .process,
                   let question = currentTurn.last(where: { $0.kind == .userMessage }) ?? contextualQuestion {
                    Button {
                        followsLatest = false
                        scroll.scrollTo(ProcessEntry.message(question).id, anchor: .top)
                    } label: {
                        HStack(spacing: 6) {
                            Text(question.questionLabel).fontWeight(.semibold)
                            Text(verbatim: question.text).lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("定位到完整提问")
                    Divider()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        switch scope {
                        case .latest:
                            VStack(alignment: .leading, spacing: 12) { latest }
                                .id("latest-top")
                        case .process:
                            if process.isEmpty {
                                Label(running ? "等待 Codex 写入过程记录" : "本轮暂无过程记录",
                                      systemImage: "clock")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(process) { entry in
                                SessionProcessRow(entry: entry).id(entry.id)
                            }
                        case .history:
                            ForEach(items) { message in
                                card(message).id(message.id)
                            }
                        }
                        ForEach(outgoing) { message in
                            SessionUserBubble(text: message.text, date: message.date, status: message.phase.label)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                }
                .onChange(of: scope, initial: true) { moveToLatest(scroll) }
                .onChange(of: followsLatest) { moveToLatest(scroll) }
                .onChange(of: items.last?.id) {
                    if scope == .history { moveToLatest(scroll) }
                }
                .onChange(of: process.last?.id) {
                    if scope == .process { moveToLatest(scroll) }
                }
                .onChange(of: turnID) {
                    priorExpanded = false
                    if scope == .latest { moveToLatest(scroll) }
                }
                .onChange(of: outgoing.last?.id) { _, new in
                    if let new {
                        scroll.scrollTo(new, anchor: .bottom)
                    } else {
                        moveToLatest(scroll)
                    }
                }
                .onChange(of: result?.id) {
                    if scope == .latest { moveToLatest(scroll) }
                }
            }
        }
    }

    @ViewBuilder
    private var latest: some View {
        if let question = contextualQuestion {
            card(question, title: question.questionLabel)
            if question.questionContext == .previous {
                Text("本轮无提问记录").font(.caption).foregroundStyle(.secondary)
            }
        }
        if !progress.isEmpty || !activities.isEmpty {
            Button {
                scope = .process
            } label: {
                HStack(spacing: 7) {
                    Label("查看本轮过程", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.caption.weight(.medium))
                .padding(8)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        ForEach(currentTurn.filter { $0.kind != .progress }) { message in
            card(message)
        }
        if result == nil {
            if let update = progress.last {
                card(update, title: "最新进度")
            } else if let event = activities.last(where: { $0.text != nil }) {
                SessionProcessRow(entry: .activity(event, count: 1))
            } else if outgoing.isEmpty || !currentTurn.isEmpty {
                Label("等待 Codex 回复", systemImage: "ellipsis.bubble")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        if result == nil, let previous = items.last(where: { $0.kind == .result }) {
            DisclosureGroup("上一轮对话", isExpanded: $priorExpanded) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(items.filter { $0.turnID == previous.turnID && $0.kind == .userMessage }) { card($0) }
                    card(previous)
                }
                .padding(.top, 7)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func card(_ message: SessionMessage, title: String? = nil) -> some View {
        if message.kind == .userMessage {
            SessionUserBubble(text: message.text, date: message.date, title: title ?? message.kind.label)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(title ?? message.kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(message.kind == .result ? Color.teal : .secondary)
                    Spacer()
                    Text(message.date.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                MessageMarkdown(source: message.text).equatable().font(.system(size: 13))
            }
            .padding(12)
            .background(.secondary.opacity(message.kind == .result ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private func moveToLatest(_ scroll: ScrollViewProxy) {
        if let pending = outgoing.last, scope == .latest || followsLatest {
            scroll.scrollTo(pending.id, anchor: .bottom)
            return
        }
        switch scope {
        case .latest:
            scroll.scrollTo("latest-top", anchor: .top)
        case .process:
            if followsLatest, let id = process.last?.id { scroll.scrollTo(id, anchor: .bottom) }
        case .history:
            if followsLatest, let id = items.last?.id { scroll.scrollTo(id, anchor: .top) }
        }
    }
}
