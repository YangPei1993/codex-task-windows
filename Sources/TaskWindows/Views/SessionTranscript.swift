import SwiftUI

struct SessionTranscript: View {
    private enum Scope: String, CaseIterable {
        case latest = "最新一轮"
        case history = "全部消息"
    }

    let items: [SessionMessage]
    @State private var scope = Scope.latest
    @State private var followsLatest = true
    @State private var requestExpanded = false
    @State private var progressExpanded = false
    @State private var priorExpanded = false

    private var currentTurn: [SessionMessage] { items.filter { $0.turnID == items.last?.turnID } }
    private var result: SessionMessage? { currentTurn.last { $0.kind == .result } }
    private var progress: [SessionMessage] { currentTurn.filter { $0.kind == .progress } }

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
                if scope == .history {
                    Toggle("跟随最新", isOn: $followsLatest).toggleStyle(.checkbox)
                }
            }
            .font(.caption)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if scope == .latest {
                            VStack(alignment: .leading, spacing: 12) { latest }
                                .id("latest-top")
                        } else {
                            ForEach(items) { message in
                                card(message).id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                }
                .onChange(of: scope) { moveToLatest(scroll) }
                .onChange(of: followsLatest) { moveToLatest(scroll) }
                .onChange(of: items.last?.id) {
                    if scope == .history { moveToLatest(scroll) }
                }
                .onChange(of: items.last?.turnID) {
                    requestExpanded = false
                    progressExpanded = false
                    priorExpanded = false
                    if scope == .latest { moveToLatest(scroll) }
                }
                .onChange(of: result?.id) {
                    if scope == .latest { moveToLatest(scroll) }
                }
            }
        }
    }

    @ViewBuilder
    private var latest: some View {
        if let result {
            card(result, title: "最新回复")
        } else if let update = progress.last {
            card(update, title: "最新进度")
        } else {
            Label("等待 Codex 回复", systemImage: "ellipsis.bubble")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        if let request = currentTurn.last(where: { $0.kind == .userMessage }) {
            DisclosureGroup("本轮请求", isExpanded: $requestExpanded) { card(request).padding(.top, 7) }
                .font(.caption)
        }
        let earlier = result == nil ? Array(progress.dropLast()) : progress
        if !earlier.isEmpty {
            DisclosureGroup("过程进度（\(earlier.count)）", isExpanded: $progressExpanded) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(earlier) { card($0) }
                }
                .padding(.top, 7)
            }
            .font(.caption)
        }
        if result == nil, let previous = items.last(where: { $0.kind == .result }) {
            DisclosureGroup("上一轮回复", isExpanded: $priorExpanded) { card(previous).padding(.top, 7) }
                .font(.caption)
        }
    }

    private func card(_ message: SessionMessage, title: String? = nil) -> some View {
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
            Group {
                if message.kind == .userMessage {
                    Text(verbatim: message.text).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MessageMarkdown(source: message.text).equatable()
                }
            }
            .font(.system(size: 13))
        }
        .padding(12)
        .background(.secondary.opacity(message.kind == .result ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private func moveToLatest(_ scroll: ScrollViewProxy) {
        if scope == .latest {
            scroll.scrollTo("latest-top", anchor: .top)
        } else if followsLatest, let id = items.last?.id {
            scroll.scrollTo(id, anchor: .top)
        }
    }
}
