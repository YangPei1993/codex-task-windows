import SwiftUI

struct OverviewView: View {
    private enum Scope: String, CaseIterable {
        case all = "全部"
        case running = "进行中"
        case open = "已开窗"
    }

    let store: SessionStore
    let open: ([Session]) -> Void
    let tile: () -> Void
    let openInCodex: (Session) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var project = ""
    @State private var scope: Scope = .all
    @State private var selection: Set<String> = []
    @State private var pendingOpen: [Session] = []
    @State private var confirmingOpen = false

    /// 一次新开窗口超过该数量时先确认，避免屏幕瞬间被铺满。
    private static let confirmThreshold = 6

    private func requestOpen(_ sessions: [Session]) {
        let newCount = sessions.filter { !store.watching.contains($0.id) }.count
        if newCount > Self.confirmThreshold {
            pendingOpen = sessions
            confirmingOpen = true
        } else {
            open(sessions)
        }
    }

    private var projects: [String] {
        Set(store.sessions.map(\.project)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var filtered: [Session] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.sessions.filter { session in
            (project.isEmpty || session.project == project) &&
            (term.isEmpty || session.title.localizedStandardContains(term) || session.project.localizedStandardContains(term))
        }
    }

    private var visible: [Session] {
        switch scope {
        case .all: filtered
        case .running: filtered.filter { $0.status == .running }
        case .open: filtered.filter { store.watching.contains($0.id) }
        }
    }

    private var selected: [Session] { visible.filter { selection.contains($0.id) } }
    private var running: [Session] { filtered.filter { $0.status == .running } }
    private var openSessions: [Session] { filtered.filter { store.watching.contains($0.id) } }
    @FocusState private var isSearchFocused: Bool

    private func scopeTitle(_ item: Scope) -> String {
        switch item {
        case .all: "全部 (\(filtered.count))"
        case .running: "进行中 (\(running.count))"
        case .open: "已开窗 (\(openSessions.count))"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filters
            Divider().opacity(0.6)
            if visible.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                sessionList
            }
            Divider().opacity(0.6)
            footer
        }
        .frame(minWidth: 640, minHeight: 440)
        .tint(.teal)
        .confirmationDialog(
            "将打开 \(pendingOpen.filter { !store.watching.contains($0.id) }.count) 个新窗口",
            isPresented: $confirmingOpen
        ) {
            Button("打开并平铺") {
                open(pendingOpen)
                tile()
                pendingOpen = []
            }
            Button("仅打开") {
                open(pendingOpen)
                pendingOpen = []
            }
            Button("取消", role: .cancel) { pendingOpen = [] }
        } message: {
            Text("窗口较多时建议平铺排列，之后也可以按 ⌘2 重新平铺。")
        }
        .background {
            // 隐藏快捷键触发⌘F快速聚焦搜索框
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: [.command])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.teal.opacity(0.22), .teal.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.teal.opacity(0.25), lineWidth: 1)
                    )
                Image(systemName: "square.on.square")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.teal)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("会话看板")
                    .font(.system(size: 20, weight: .bold))
                HStack(spacing: 8) {
                    statPill(title: "总会话", count: filtered.count, tint: .secondary)
                    statPill(title: "进行中", count: running.count, tint: .blue, active: !running.isEmpty, pulses: !running.isEmpty)
                    statPill(title: "已开窗", count: openSessions.count, tint: .teal, active: !openSessions.isEmpty)
                }
            }
            Spacer()
            Button(action: tile) {
                Label("平铺窗口", systemImage: "square.grid.2x2")
            }
            .controlSize(.regular)
            .disabled(store.watching.isEmpty)
            .help("平铺已打开的任务窗口（⌘2）")

            Button {
                requestOpen(selected.isEmpty ? running : selected)
            } label: {
                Label(
                    selected.isEmpty ? "打开进行中 (\(running.count))" : "打开所选 (\(selected.count))",
                    systemImage: "macwindow.badge.plus"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(selected.isEmpty && running.isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("打开选中的会话，未选择时批量打开进行中会话（⌘↩）")
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func statPill(title: String, count: Int, tint: Color, active: Bool = false, pulses: Bool = false) -> some View {
        HStack(spacing: 4) {
            if active {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: pulses && !reduceMotion)
                    .accessibilityHidden(true)
            }
            Text("\(title) \(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .foregroundStyle(active ? tint : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            (active ? tint.opacity(0.12) : Color.secondary.opacity(0.08)),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(active ? tint.opacity(0.25) : .clear, lineWidth: 1)
        )
    }

    private var filters: some View {
        HStack(spacing: 10) {
            // C 端自定义胶囊/圆角搜索框，带放大镜图标和一键清除按钮
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSearchFocused ? .teal : .secondary)
                TextField("搜索标题或项目 (⌘F)", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .accessibilityLabel("搜索会话")
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清空搜索")
                    .accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSearchFocused ? Color.teal.opacity(0.6) : Color.secondary.opacity(0.22), lineWidth: 1)
            )

            Picker("项目", selection: $project) {
                Text("所有项目").tag("")
                ForEach(projects, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 168)
            .help("按项目筛选会话")

            Picker("会话状态", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { item in
                    Text(scopeTitle(item)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private var emptyState: some View {
        Group {
            if store.lastRefresh == nil, store.error == nil {
                ProgressView("正在读取本地 Codex 会话…")
            } else if let error = store.error, store.sessions.isEmpty {
                ContentUnavailableView("暂时无法读取会话", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(error))
            } else {
                ContentUnavailableView {
                    Label("没有符合条件的会话", systemImage: "magnifyingglass")
                } description: {
                    Text("可以尝试切换筛选范围，或清空当前搜索条件。")
                } actions: {
                    if !search.isEmpty || !project.isEmpty || scope != .all {
                        Button("重置筛选条件") {
                            search = ""
                            project = ""
                            scope = .all
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var sessionList: some View {
        List(selection: $selection) {
            ForEach(visible) { session in
                let isWatching = store.watching.contains(session.id)
                let isPinned = store.pinned.contains(session.id)
                HStack(spacing: 12) {
                    // 左侧图标容器：提升视觉层级与已开窗辨识度
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isWatching ? Color.teal.opacity(0.14) : Color.secondary.opacity(0.08))
                        Image(systemName: isWatching ? "macwindow.on.rectangle" : "bubble.left.and.text.bubble.right")
                            .font(.system(size: 13, weight: isWatching ? .semibold : .regular))
                            .foregroundStyle(isWatching ? .teal : .secondary)
                    }
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(verbatim: session.title)
                                .font(.system(size: 13.5, weight: isWatching ? .semibold : .medium))
                                .lineLimit(1)
                                .help(session.title)
                            if isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.teal)
                                    .help("窗口已置顶")
                            }
                        }
                        HStack(spacing: 6) {
                            Label(session.project, systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            if let lastAction = session.lastAction {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(lastAction)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    StatusBadge(status: session.status, animates: true)

                    Text(Session.friendlyTimestamp(session.sortDate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 96, alignment: .trailing)
                        .help(session.sortDate.formatted(date: .abbreviated, time: .standard))

                    Button {
                        open([session])
                    } label: {
                        Image(systemName: isWatching ? "macwindow" : "arrow.up.right.square")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isWatching ? .teal : .secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.borderless)
                    .help(isWatching ? "前置已打开的窗口" : "打开独立监控窗口")
                    .accessibilityLabel(isWatching ? "前置已打开的窗口" : "打开独立监控窗口")
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .tag(session.id)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: String.self) { ids in
            let targets = visible.filter { ids.contains($0.id) }
            Button(ids.count <= 1 ? "打开独立窗口" : "打开所选（\(ids.count)）") {
                requestOpen(targets)
            }
            .disabled(targets.isEmpty)
            if targets.count == 1, let item = targets.first {
                Button("在原 Codex 中打开") {
                    openInCodex(item)
                }
                Divider()
                Button("复制会话标题") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.title, forType: .string)
                }
            }
        } primaryAction: { ids in
            requestOpen(visible.filter { ids.contains($0.id) })
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .lineLimit(1)
                    .foregroundStyle(.orange)
            } else if let refreshed = store.lastRefresh {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("实时同步 · \(refreshed.formatted(.dateTime.hour().minute().second()))")
                        .monospacedDigit()
                }
                .accessibilityLabel("上次本地同步 \(refreshed.formatted(date: .omitted, time: .standard))")
            } else {
                Text("正在连接本地记录…")
            }
            Spacer(minLength: 8)
            if !selected.isEmpty {
                Text("已选 \(selected.count) 项")
                    .fontWeight(.medium)
                    .foregroundStyle(.teal)
                Text("·")
            }
            Text("双击或 ⌘↩ 开窗 · ⌘F 搜索")
            Button(action: store.requestRefresh) {
                Label("刷新", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("立即刷新本地记录（⌘R）")
            .accessibilityLabel("刷新")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
