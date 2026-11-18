import Foundation

enum CodexQueue {
    static let messageLimit = 64 * 1024
    private static let bundledCLI = "Contents/Resources/codex-cli/bin/codex"

    enum SubmitError: LocalizedError {
        case unavailable, invalidInput, launchFailed, rejected, confirmationMissing

        var errorDescription: String? {
            switch self {
            case .unavailable: "找不到 Codex CLI。可在原会话继续发送。"
            case .invalidInput: "请输入有效文字，单条消息最多 64 KB。"
            case .launchFailed: "无法启动 Codex CLI，草稿已保留。"
            case .rejected: "Codex 未能确认排队，草稿已保留。请先到原会话检查队列。"
            case .confirmationMissing: "没有收到排队回执，草稿已保留。请先到原会话确认再重试。"
            }
        }
    }

    @MainActor
    static func submit(_ message: String, to session: Session) async throws {
        guard session.acceptsMessages, let url = session.deepLink else { throw SubmitError.unavailable }
        guard let application = CodexLink.application(for: url) else { throw SubmitError.unavailable }
        let executable = application.appendingPathComponent(bundledCLI)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw SubmitError.unavailable }
        try await Task.detached(priority: .userInitiated) {
            try enqueue(message, threadID: session.id, executable: executable)
        }.value
    }

    static func enqueue(_ message: String, threadID: String, executable: URL) throws {
        guard UUID(uuidString: threadID) != nil, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !message.contains("\0"), message.utf8.count <= messageLimit else { throw SubmitError.invalidInput }

        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.arguments = ["queue", "--thread", threadID, "--message=\(message)"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw SubmitError.launchFailed
        }

        let deadline = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: deadline)
        defer { deadline.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        let accepted = lines.contains { line in
            line.hasPrefix("Queued message ") && line.trimmingCharacters(in: CharacterSet(charactersIn: ". \r"))
                .lowercased().hasSuffix(" for thread \(threadID.lowercased())")
        }
        if accepted { return }
        guard process.terminationReason == .exit, process.terminationStatus != 0 else {
            throw SubmitError.confirmationMissing
        }
        throw SubmitError.rejected
    }
}
