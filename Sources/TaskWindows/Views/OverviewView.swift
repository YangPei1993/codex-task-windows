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
    @State private var search = ""
    @State private var project = ""
    @State private var scope: Scope = .all
    @State private var selection: Set<String> = []

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

    var body: some View {
        VStack(spacing: 0) {
            header
            filters
            Divider()
            if visible.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                sessionList
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 420)
        .tint(.teal)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "square.on.square")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.teal)
                .frame(width: 42, height: 42)
                .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("会话看板").font(.title2.weight(.semibold))
                Text("\(filtered.count) 条会话 · \(running.count) 条进行中 · \(store.watching.count) 个窗口")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: tile) { Label("平铺窗口", systemImage: "square.grid.2x2") }
                .disabled(store.watching.isEmpty)
                .help("平铺已打开的任务窗口（⌘2）")
            Button {
                open(selected.isEmpty ? running : selected)
            } label: {
                Label(selected.isEmpty ? "打开进行中" : "打开所选（\(selected.count)）", systemImage: "macwindow.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty && running.isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var filters: some View {
        HStack(spacing: 10) {
            TextField("搜索标题、工单或项目", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("搜索会话")
            Picker("项目", selection: $project) {
                Text("所有项目").tag("")
                ForEach(projects, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 162)
            Picker("会话状态", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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
                ProgressView("正在读取本地 Codex 会话")
            } else if let error = store.error, store.sessions.isEmpty {
                ContentUnavailableView("暂时无法读取会话", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(error))
            } else {
                ContentUnavailableView("没有符合条件的会话", systemImage: "magnifyingglass",
                                       description: Text("试试切换项目或清空搜索。"))
            }
        }
    }

    private var sessionList: some View {
        List(selection: $selection) {
            ForEach(visible) { session in
                HStack(spacing: 12) {
                    Image(systemName: store.watching.contains(session.id) ? "macwindow" : "text.bubble")
                        .font(.system(size: 15))
                        .foregroundStyle(store.watching.contains(session.id) ? .teal : .secondary)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: session.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .help(session.title)
                        Text(verbatim: session.project)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    StatusBadge(status: session.status)
                    Text(session.sortDate.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 114, alignment: .trailing)
                    Button {
                        open([session])
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 15))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.borderless)
                    .help("打开独立窗口")
                    .accessibilityLabel("打开独立窗口")
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .tag(session.id)
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            Button(ids.count == 1 ? "打开独立窗口" : "打开所选") {
                open(visible.filter { ids.contains($0.id) })
            }
            .disabled(ids.isEmpty)
        } primaryAction: { ids in
            open(visible.filter { ids.contains($0.id) })
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.circle").lineLimit(1).foregroundStyle(.orange)
            } else if let refreshed = store.lastRefresh {
                Label("本地同步 \(refreshed.formatted(.dateTime.hour().minute().second()))", systemImage: "arrow.clockwise")
                    .accessibilityLabel("上次本地同步 \(refreshed.formatted(date: .omitted, time: .standard))")
            } else {
                Text("连接本地记录…")
            }
            Spacer(minLength: 8)
            Text("双击开窗 · ⌘ 点击多选")
            Button(action: store.requestRefresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("刷新（⌘R）")
                .accessibilityLabel("刷新")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
    }
}

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.tint).frame(width: 5, height: 5).accessibilityHidden(true)
            Text(status.label).font(.caption.weight(.medium)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.tint.opacity(0.15), in: Capsule())
        .help(status == .uncertain ? "最近 5 分钟没有新的本地活动，实际状态请回 Codex 查看。" : "最近一轮会话状态")
    }
}
