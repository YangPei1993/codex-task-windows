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

    private func scopeTitle(_ item: Scope, compact: Bool, activityCount: Int) -> String {
        if compact { return item.rawValue }
        switch item {
        case .latest: return item.rawValue
        case .process: return activityCount == 0 ? item.rawValue : "过程 (\(activityCount))"
        case .history: return items.isEmpty ? item.rawValue : "全部 (\(items.count))"
        }
    }

    private func toolbar(compact: Bool, activityCount: Int) -> some View {
        HStack(spacing: 8) {
            Picker("消息范围", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { item in
                    Text(scopeTitle(item, compact: compact, activityCount: activityCount)).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: compact ? 212 : 265)
            Spacer(minLength: 0)
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
                .overlay(
                    Capsule().strokeBorder(followsLatest ? Color.teal.opacity(0.25) : .clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .opacity(scope == .latest ? 0 : 1)
            .allowsHitTesting(scope != .latest)
            .disabled(scope == .latest)
            .accessibilityHidden(scope == .latest)
            .accessibilityLabel("跟随最新")
            .accessibilityValue(followsLatest ? "已开启" : "已暂停")
            .help(followsLatest ? "正在自动滚动到最新内容（点击暂停）" : "点击恢复自动跟随最新内容")
        }
    }

    var body: some View {
        let entries = process
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                toolbar(compact: false, activityCount: entries.count)
                toolbar(compact: true, activityCount: entries.count)
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
                    LazyVStack(alignment: .leading, spacing: 15) {
                        switch scope {
                        case .latest:
                            VStack(alignment: .leading, spacing: 15) { latest(activityCount: entries.count) }
                                .id("latest-top")
                        case .process:
                            if entries.isEmpty {
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
                            ForEach(entries) { entry in
                                SessionProcessRow(entry: entry, isLatest: entry.id == entries.last?.id)
                                    .id(entry.id)
                            }
                        case .history:
                            ForEach(items) { message in
                                card(message, collapsible: true, initiallyExpanded: message.id == items.last?.id)
                                    .id(message.id)
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
                .onChange(of: entries.last?.id) {
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
    private func latest(activityCount: Int) -> some View {
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
                    Text("查看本轮思考与执行过程 (\(activityCount))")
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
                        .strokeBorder(Color.teal.opacity(0.22), lineWidth: 1)
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
    private func card(_ message: SessionMessage, title: String? = nil,
                      collapsible: Bool = false, initiallyExpanded: Bool = true) -> some View {
        if message.kind == .userMessage {
            SessionUserBubble(text: message.text, date: message.date, title: title ?? message.kind.label)
        } else {
            MessageResponseCard(message: message, title: title ?? message.kind.label,
                                collapsible: collapsible, initiallyExpanded: initiallyExpanded)
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
    let collapsible: Bool
    @State private var copied = false
    @State private var expanded: Bool

    init(message: SessionMessage, title: String, collapsible: Bool, initiallyExpanded: Bool) {
        self.message = message
        self.title = title
        self.collapsible = collapsible
        _expanded = State(initialValue: initiallyExpanded)
    }

    private var isResult: Bool { message.kind == .result }

    private var isLong: Bool {
        collapsible && (message.text.count > 160 || message.text.split(separator: "\n", omittingEmptySubsequences: false).count > 4)
    }

    private var previewText: String {
        message.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: isResult ? "sparkles" : "bolt.horizontal.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isResult ? Color.teal : .secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isResult ? Color.teal : .secondary)
                Text(Session.friendlyTimestamp(message.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(message.date.formatted(date: .abbreviated, time: .standard))
                Spacer()

                if isLong {
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

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12, height: 12)
                        .foregroundStyle(copied ? .teal : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(copied ? "已复制" : "复制消息全文")
                .accessibilityLabel(copied ? "已复制" : "复制消息全文")
            }

            if isLong && !expanded {
                Text(verbatim: previewText)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .foregroundStyle(.primary.opacity(0.82))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    expanded = true
                } label: {
                    HStack(spacing: 3) {
                        Text("展开全文")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.teal)
                }
                .buttonStyle(.plain)
            } else {
                MessageMarkdown(source: message.text).equatable().font(.system(size: 13))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            isResult ? Color.teal.opacity(0.055) : Color.secondary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isResult ? Color.teal.opacity(0.22) : Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }
}
