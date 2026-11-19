import AppKit
import SwiftUI

@MainActor
final class SessionWindows: NSObject, NSWindowDelegate {
    private let store: SessionStore
    private var overview: NSWindow?
    private var windows: [String: NSWindow] = [:]
    private var openOrder: [String] = []

    init(store: SessionStore) {
        self.store = store
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
            if let previous = openOrder.last.flatMap({ windows[$0] }) {
                window.cascadeTopLeft(from: .init(x: previous.frame.minX, y: previous.frame.maxY))
            } else {
                window.center()
            }
            windows[session.id] = window
            openOrder.append(session.id)
            store.startWatching(session.id)
            reveal(window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === overview { overview = nil }
        guard let id = window.identifier?.rawValue, windows[id] === window else { return }
        windows[id] = nil
        openOrder.removeAll { $0 == id }
        store.stopWatching(id)
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
        // 超出屏幕可平铺数量的窗口保留原位置。
    }

    private func setPinned(_ id: String) {
        guard let window = windows[id] else { return }
        let enabled = !store.pinned.contains(id)
        window.level = enabled ? .floating : .normal
        store.setPinned(id, enabled)
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
