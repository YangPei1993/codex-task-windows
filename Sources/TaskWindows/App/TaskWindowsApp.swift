import AppKit
import SwiftUI

@main
@MainActor
enum TaskWindowsApp {
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--verify-data" {
            verifyData(project: CommandLine.arguments.dropFirst(2).first)
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    private static func verifyData(project: String?) {
        do {
            let feed = CodexFeed(directory: SessionStore.codexDirectory)
            let snapshot = try feed.fetch(watching: [])
            let sessions = snapshot.sessions.filter { project == nil || $0.project == project }
            let watched = Set(sessions.prefix(5).map(\.id))
            let details = try feed.fetch(watching: watched)
            let distinct = Set(sessions.map(\.id)).count == sessions.count
            let messageCount = details.messages.values.reduce(0) { $0 + $1.count }
            let eventCount = details.activities.values.reduce(0) { $0 + $1.count }
            let summaryCount = details.activities.values.reduce(0) { $0 + $1.filter { $0.kind == .summary }.count }
            print("会话 \(sessions.count) 条，进行中 \(sessions.filter { $0.status == .running }.count) 条，窗口样本消息 \(messageCount) 条。")
            print("本轮活动样本 \(eventCount) 条，其中公开思考摘要 \(summaryCount) 条。")
            guard !sessions.isEmpty, distinct, messageCount > 0 else { exit(1) }
            guard sessions.allSatisfy({ $0.deepLink != nil }), let link = sessions.first?.deepLink,
                  let handler = CodexLink.application(for: link) else {
                print("找不到支持 Codex 会话链接的桌面应用。")
                exit(1)
            }
            print("会话 ID 无重复，已找到会话链接处理程序：\(handler.lastPathComponent)。")
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let store = SessionStore()
    private lazy var windows = SessionWindows(store: store)
    private let notifier = StatusNotifier()
    private var pendingRestore: [String]?
    private var refreshLoop: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()
        windows.showOverview()
        NSApp.activate(ignoringOtherApps: true)
        notifier.activate = { [weak self] id in self?.windows.reveal(sessionID: id) }
        notifier.isFocused = { [weak self] id in self?.windows.isFocused(sessionID: id) == true }
        // 先把上次的窗口加入监看，使超出最近 400 条的会话也能被查询到，首次刷新成功后再恢复窗口。
        pendingRestore = windows.savedSessionIDs
        store.preloadWatching(pendingRestore ?? [])
        refreshLoop = Task {
            while !Task.isCancelled {
                await store.refresh()
                if let ids = pendingRestore, store.lastRefresh != nil {
                    pendingRestore = nil
                    windows.restore(ids)
                    store.releasePreloaded()
                }
                notifier.observe(store.sessions, watching: store.watching)
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showOverview()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windows.prepareForTermination()
        store.persistDrafts()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshLoop?.cancel()
    }

    @objc private func showOverview() { windows.showOverview() }
    @objc private func tileWindows() { windows.tile() }
    @objc private func closeAllTaskWindows() { windows.closeAllTaskWindows() }
    @objc private func refresh() { store.requestRefresh() }
    @objc private func toggleNotifications() { notifier.isEnabled.toggle() }
    @objc private func undoEdit() { editingUndoManager?.undo() }
    @objc private func redoEdit() { editingUndoManager?.redo() }

    private var editingUndoManager: UndoManager? {
        NSApp.keyWindow?.firstResponder?.undoManager
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleNotifications) {
            menuItem.state = notifier.isEnabled ? .on : .off
        }
        return switch menuItem.action {
        case #selector(undoEdit): editingUndoManager?.canUndo == true
        case #selector(redoEdit): editingUndoManager?.canRedo == true
        case #selector(tileWindows), #selector(closeAllTaskWindows): windows.hasTaskWindows
        default: true
        }
    }

    private func installMenus() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let editItem = NSMenuItem()
        let windowItem = NSMenuItem()
        bar.addItem(appItem)
        bar.addItem(editItem)
        bar.addItem(windowItem)

        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "任务结束时通知", action: #selector(toggleNotifications), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出会话窗口", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: #selector(undoEdit), keyEquivalent: "z").target = self
        let redo = editMenu.addItem(withTitle: "重做", action: #selector(redoEdit), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = self
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "会话看板", action: #selector(showOverview), keyEquivalent: "1").target = self
        windowMenu.addItem(withTitle: "平铺任务窗口", action: #selector(tileWindows), keyEquivalent: "2").target = self
        windowMenu.addItem(withTitle: "刷新", action: #selector(refresh), keyEquivalent: "r").target = self
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let closeAll = windowMenu.addItem(withTitle: "关闭全部任务窗口", action: #selector(closeAllTaskWindows), keyEquivalent: "w")
        closeAll.keyEquivalentModifierMask = [.command, .option]
        closeAll.target = self
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = bar
    }
}
