import AppKit

@MainActor
enum CodexLink {
    enum LinkError: LocalizedError {
        case invalidID, missingApplication

        var errorDescription: String? {
            switch self {
            case .invalidID: "这条会话没有有效的本地会话 ID。"
            case .missingApplication: "找不到支持 Codex 会话链接的桌面应用。"
            }
        }
    }

    private static let bundleID = "com.openai.codex"

    static func application(for url: URL) -> URL? {
        let workspace = NSWorkspace.shared
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).compactMap(\.bundleURL)
        let registered = [workspace.urlForApplication(toOpen: url), workspace.urlForApplication(withBundleIdentifier: bundleID)]
            .compactMap { $0 }
        let installed = ["ChatGPT.app", "Codex.app"].map {
            URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent($0)
        }
        return (running + registered + installed).first { candidate in
            guard let bundle = Bundle(url: candidate), bundle.bundleIdentifier == bundleID,
                  let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else { return false }
            return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("codex") == true }
        }
    }

    static func open(_ url: URL?) async throws {
        guard let url else { throw LinkError.invalidID }
        guard let application = application(for: url) else { throw LinkError.missingApplication }
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: .init())
    }
}
