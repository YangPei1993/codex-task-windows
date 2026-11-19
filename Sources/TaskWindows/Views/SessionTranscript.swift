import AppKit
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

    private func scopeTitle(_ item: Scope, compact: Bool) -> String {
        if compact { return item.rawValue }
        switch item {
        case .latest: return item.rawValue
        case .process: return process.isEmpty ? item.rawValue : "过程 (\(process.count))"
        case .history: return items.isEmpty ? item.rawValue : "全部 (\(items.count))"
        }
    }

    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Picker("消息范围", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { item in
                    Text(scopeTitle(item, compact: compact)).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer(minLength: 0)
            if scope != .latest {
                Button {
                    followsLatest.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: followsLatest ? "arrow.down.to.line.circle.fill" : "arrow.down.to.line.circle")
                        if !compact {
                            Text("跟随最新")
                        }
                    }
                    .fixedSize()
                    .font(.caption.weight(.medium))
                    .foregroundStyle(followsLatest ? .teal : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        followsLatest ? Color.teal.opacity(0.12) : Color.secondary.opacity(0.08),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("跟随最新")
                .accessibilityValue(followsLatest ? "已开启" : "已暂停")
                .help(followsLatest ? "正在自动滚动到最新内容（点击暂停）" : "点击恢复自动跟随最新内容")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                toolbar(compact: false)
                toolbar(compact: true)
            }
            .font(.caption)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            Divider().opacity(0.6)
            ScrollViewReader { scroll in
                if scope == .process,
                   let question = currentTurn.last(where: { $0.kind == .userMessage }) ?? contextualQuestion {
                    Button {
                        followsLatest = false
                        scroll.scrollTo(ProcessEntry.message(question).id, anchor: .top)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.teal)
                            Text(question.questionLabel)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text(verbatim: question.text)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.circle")
                                .foregroundStyle(.teal)
                        }
                        .font(.caption)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 7)
                        .background(Color.teal.opacity(0.05))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("点击定位到本轮完整提问")
                    Divider().opacity(0.6)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        switch scope {
                        case .latest:
                            VStack(alignment: .leading, spacing: 12) { latest }
                                .id("latest-top")
                        case .process:
                            if process.isEmpty {
                                HStack(spacing: 8) {
                                    if running {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "clock")
                                    }
                                    Text(running ? "正在等待 Codex 写入本轮过程记录…" : "本轮暂无过程记录")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 28)
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
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .foregroundStyle(.teal)
                    Text("查看本轮思考与执行过程 (\(process.count))")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("展开")
                        .foregroundStyle(.teal)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.teal)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 8.5)
                .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.teal.opacity(0.2), lineWidth: 1)
                )
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
                HStack(spacing: 8) {
                    if running {
                        ProgressView().controlSize(.small)
                        Text("Codex 正在思考与处理…")
                    } else {
                        Image(systemName: "bubble.left")
                        Text("本轮暂无可显示的回复")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
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
            MessageResponseCard(message: message, title: title ?? message.kind.label)
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

private struct MessageResponseCard: View {
    let message: SessionMessage
    let title: String
    @State private var copied = false

    private var isResult: Bool { message.kind == .result }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: isResult ? "sparkles" : "bolt.horizontal.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isResult ? Color.teal : .secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isResult ? Color.teal : .secondary)
                Spacer()
                Text(Session.friendlyTimestamp(message.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(message.date.formatted(date: .abbreviated, time: .standard))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        if copied {
                            Text("已复制").font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundStyle(copied ? .teal : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("复制消息全文")
                .accessibilityLabel("复制消息全文")
            }
            MessageMarkdown(source: message.text).equatable().font(.system(size: 13))
        }
        .padding(12)
        .background(
            isResult ? Color.teal.opacity(0.05) : Color.secondary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isResult ? Color.teal.opacity(0.18) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
