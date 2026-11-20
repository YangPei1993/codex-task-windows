import AppKit
import SwiftUI

@MainActor
final class SessionWindows: NSObject, NSWindowDelegate {
    private static let openKey = "openSessionIDs"
    private static let pinnedKey = "pinnedSessionIDs"

    private let store: SessionStore
    private var overview: NSWindow?
    private var windows: [String: NSWindow] = [:]
    private var openOrder: [String] = []
    // 退出过程中窗口关闭不应清掉待恢复的列表。
    private var terminating = false

    init(store: SessionStore) {
        self.store = store
    }

    /// 上次退出时仍打开的任务窗口（按打开顺序）。
    var savedSessionIDs: [String] {
        UserDefaults.standard.stringArray(forKey: Self.openKey) ?? []
    }

    var hasTaskWindows: Bool { !windows.isEmpty }

    /// 恢复上次的任务窗口和置顶状态；会话已不存在的跳过。
    func restore(_ ids: [String]) {
        let pinnedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? [])
        let sessions = ids.compactMap { id in store.sessions.first { $0.id == id } }
        open(sessions)
        for session in sessions where pinnedIDs.contains(session.id) && !store.pinned.contains(session.id) {
            setPinned(session.id)
        }
        if let overview { reveal(overview) }
    }

    func prepareForTermination() {
        // 开窗、关窗和置顶变更已即时保存；首次恢复未完成时保留已有记录。
        terminating = true
    }

    func closeAllTaskWindows() {
        for id in openOrder.reversed() {
            windows[id]?.performClose(nil)
        }
    }

    private func persist() {
        guard !terminating else { return }
        UserDefaults.standard.set(openOrder, forKey: Self.openKey)
        UserDefaults.standard.set(openOrder.filter { store.pinned.contains($0) }, forKey: Self.pinnedKey)
    }

    func showOverview() {
        if let overview {
            reveal(overview)
            return
        }
        let view = OverviewView(
            store: store, open: { [weak self] in self?.open($0) }, tile: { [weak self] in self?.tile() },
            openInCodex: { [weak self] session in
                self?.openInCodex(session, from: self?.overview)
            }
        )
        let window = makeWindow(title: "Codex 会话看板", view: view, size: .init(width: 860, height: 620),
                                minimum: .init(width: 640, height: 440))
        window.center()
        window.setFrameAutosaveName("SessionOverview")
        overview = window
        reveal(window)
    }

    func open(_ sessions: [Session]) {
        for session in sessions {
            if let window = windows[session.id] {
                reveal(window)
                continue
            }
            let view = SessionView(
                store: store, original: session, draft: store.draft(for: session.id),
                pin: { [weak self] in self?.setPinned(session.id) },
                openInCodex: { [weak self] in self?.openInCodex(session) }
            )
            let window = makeWindow(title: session.title, view: view, size: .init(width: 520, height: 530),
                                    minimum: .init(width: 320, height: 280))
            // 内容顶部已有任务标题，标题栏留给窗口按钮和状态。
            window.titleVisibility = .hidden
            let status = SessionWindowStatus(store: store, original: session,
                                             openInCodex: { [weak self] in self?.openInCodex(session) })
            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = .trailing
            let statusView = NSHostingView(rootView: status)
            statusView.frame.size = statusView.fittingSize
            accessory.view = statusView
            window.addTitlebarAccessoryViewController(accessory)
            window.identifier = NSUserInterfaceItemIdentifier(session.id)
            // 每个会话记住自己的窗口位置；首次打开时沿用层叠/居中。
            let frameName = "SessionWindow-\(session.id)"
            if !window.setFrameUsingName(frameName) {
                if let previous = openOrder.last.flatMap({ windows[$0] }) {
                    window.cascadeTopLeft(from: .init(x: previous.frame.minX, y: previous.frame.maxY))
                } else {
                    window.center()
                }
            }
            window.setFrameAutosaveName(frameName)
            windows[session.id] = window
            openOrder.append(session.id)
            store.startWatching(session.id)
            persist()
            reveal(window)
        }
    }

    /// 按会话 ID 前置窗口；窗口已关闭时重新打开。
    func reveal(sessionID id: String) {
        if let window = windows[id] {
            reveal(window)
        } else if let session = store.sessions.first(where: { $0.id == id }) {
            open([session])
        }
    }

    func isFocused(sessionID id: String) -> Bool {
        NSApp.isActive && NSApp.keyWindow != nil && NSApp.keyWindow === windows[id]
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === overview { overview = nil }
        guard let id = window.identifier?.rawValue, windows[id] === window else { return }
        windows[id] = nil
        openOrder.removeAll { $0 == id }
        store.stopWatching(id)
        persist()
    }

    func tile() {
        var pending = openOrder.compactMap { windows[$0] }
        let preferred = NSApp.keyWindow?.screen ?? NSScreen.main
        let screens = preferred.map { screen in [screen] + NSScreen.screens.filter { $0 != screen } } ?? NSScreen.screens
        for screen in screens where !pending.isEmpty {
            let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            let maxColumns = max(1, Int(area.width / 330))
            let maxRows = max(1, Int(area.height / 320))
            let count = min(pending.count, maxColumns * maxRows)
            let idealColumns = Int(ceil(sqrt(Double(count) * Double(area.width / area.height) / 1.45)))
            let columns = min(count, maxColumns, max(1, idealColumns, (count + maxRows - 1) / maxRows))
            let rows = (count + columns - 1) / columns
            let width = area.width / CGFloat(columns)
            let height = area.height / CGFloat(rows)
            for (index, window) in pending.prefix(count).enumerated() {
                let x = area.minX + CGFloat(index % columns) * width
                let y = area.maxY - CGFloat(index / columns + 1) * height
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.setFrame(NSRect(x: x + 4, y: y + 4, width: width - 8, height: height - 8), display: true)
                window.orderFront(nil)
            }
            pending.removeFirst(count)
        }
        // 所有屏幕都放不下时，剩余窗口在首选屏幕上层叠排列，避免被遗漏在原位置。
        guard !pending.isEmpty, let screen = screens.first else { return }
        var origin = NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 40)
        for window in pending {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.setContentSize(NSSize(width: 520, height: 530))
            origin = window.cascadeTopLeft(from: origin)
            window.orderFront(nil)
        }
    }

    private func setPinned(_ id: String) {
        guard let window = windows[id] else { return }
        let enabled = !store.pinned.contains(id)
        window.level = enabled ? .floating : .normal
        store.setPinned(id, enabled)
        persist()
    }

    private func openInCodex(_ session: Session, from parent: NSWindow? = nil) {
        Task {
            do {
                try await CodexLink.open(session.deepLink)
            } catch {
                let alert = NSAlert()
                alert.messageText = "无法打开 Codex 会话"
                alert.informativeText = error.localizedDescription
                if let window = parent ?? windows[session.id], window.isVisible {
                    alert.beginSheetModal(for: window, completionHandler: nil)
                } else {
                    alert.runModal()
                }
            }
        }
    }

    private func makeWindow<Content: View>(title: String, view: Content, size: NSSize, minimum: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: .init(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(rootView: view)
        window.contentMinSize = minimum
        window.setContentSize(size)
        return window
    }

    private func reveal(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}
