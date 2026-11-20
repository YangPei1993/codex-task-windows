import AppKit
import UserNotifications

/// 已开窗会话的状态从「进行中」变为结束态时发系统通知，并在 Dock 图标上显示进行中的会话数。
@MainActor
final class StatusNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let enabledKey = "notifyStatusChanges"
    private nonisolated static let sessionKey = "sessionID"

    /// 点击通知时前置对应会话窗口。
    var activate: ((String) -> Void)?
    /// 用户正在看的窗口不再重复提醒。
    var isFocused: ((String) -> Bool)?

    private var lastStatus: [String: SessionStatus] = [:]
    // 未打包成 .app 直接运行时没有 bundle identifier，UNUserNotificationCenter 会崩溃，此时只更新 Dock 标记。
    private let center: UNUserNotificationCenter? = Bundle.main.bundleIdentifier == nil ? nil : .current()

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    override init() {
        super.init()
        center?.delegate = self
    }

    func observe(_ sessions: [Session], watching: Set<String>) {
        let running = sessions.filter { $0.status == .running }.count
        NSApp.dockTile.badgeLabel = running > 0 ? "\(running)" : nil

        var next: [String: SessionStatus] = [:]
        for session in sessions where watching.contains(session.id) {
            next[session.id] = session.status
            // 仅提醒「进行中 → 完成/失败/待确认」；中断通常由用户主动触发，不提醒。
            guard lastStatus[session.id] == .running,
                  [.completed, .failed, .uncertain].contains(session.status),
                  isEnabled, isFocused?(session.id) != true else { continue }
            post(session)
        }
        lastStatus = next
    }

    private func post(_ session: Session) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(session.status.label) · \(session.title)"
        content.body = session.lastAction ?? session.status.explanation
        content.subtitle = session.project
        content.threadIdentifier = session.id
        content.userInfo = [Self.sessionKey: session.id]
        if session.status != .completed { content.sound = .default }
        let request = UNNotificationRequest(identifier: "\(session.id)-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        Task {
            // 首次需要提醒时才申请权限，避免启动即弹窗；已决定过的权限不会重复询问。
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo[Self.sessionKey] as? String else { return }
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            activate?(id)
        }
    }
}
