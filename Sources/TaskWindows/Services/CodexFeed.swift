import Foundation
import SQLite3

struct FeedSnapshot {
    var sessions: [Session]
    var messages: [String: [SessionMessage]]
}

struct DatabaseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class CodexFeed {
    private var database: OpaquePointer?
    private let directory: URL
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) {
        self.directory = directory
    }

    deinit { reset() }

    func fetch(watching: Set<String>, now: Date = .now) throws -> FeedSnapshot {
        do {
            try openIfNeeded()
            // 将会话索引和进度投影限制在同一次只读事务里。
            try query("BEGIN")
            var snapshot = FeedSnapshot(sessions: try recentAndWatched(watching, now: now), messages: [:])
            for id in watching {
                snapshot.messages[id] = try messages(for: id)
            }
            try query("COMMIT")
            return snapshot
        } catch {
            reset()
            throw error
        }
    }

    private func openIfNeeded() throws {
        guard database == nil else { return }
        let state = directory.appendingPathComponent("state_5.sqlite")
        let history = directory.appendingPathComponent("thread_history_1.sqlite")
        guard FileManager.default.isReadableFile(atPath: state.path),
              FileManager.default.isReadableFile(atPath: history.path) else {
            throw DatabaseError(message: "找不到可读取的 Codex 会话数据库。请先在本机打开 Codex 并运行一次会话。")
        }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(state.path, &database, flags, nil) == SQLITE_OK else {
            throw sqliteError()
        }
        sqlite3_busy_timeout(database, 800)
        try query("ATTACH DATABASE ? AS history", bindings: [history.absoluteString + "?mode=ro"])
        try query("PRAGMA query_only = ON")
    }

    private func reset() {
        if let database { sqlite3_close(database) }
        database = nil
    }

    private func recentAndWatched(_ watching: Set<String>, now: Date) throws -> [Session] {
        let ids = watching.sorted()
        let watchedFilter = ids.isEmpty ? "" : "OR t.id IN (\(ids.map { _ in "?" }.joined(separator: ",")))"
        var sessions: [Session] = []
        try query("""
            WITH recent AS (
                SELECT id
                FROM threads
                WHERE archived = 0 AND attached_thread_parent_id IS NULL
                    AND source NOT LIKE '%"subagent"%'
                    AND preview <> ''
                ORDER BY recency_at_ms DESC
                LIMIT 400
            )
            SELECT t.id, COALESCE(NULLIF(t.name, ''), NULLIF(t.title, ''), '未命名会话'),
                   COALESCE(NULLIF(p.name, ''), t.cwd), p.name IS NOT NULL,
                   COALESCE(t.updated_at_ms, t.updated_at * 1000),
                   turn.status, COALESCE(turn.started_at, 0) * 1000,
                   max(item.created_at_ms, COALESCE(item.completed_at_ms, 0), COALESCE(item.started_at_ms, 0)), item.item_type,
                   t.archived = 0 AND t.source IN ('vscode', 'cli')
                       AND COALESCE(t.originator, '') != 'openclaw'
                       AND COALESCE(t.thread_source, '') IN ('', 'user', 'agent_created_thread')
            FROM threads t
            LEFT JOIN projects p ON p.id = t.project_id
            LEFT JOIN history.thread_turns turn ON turn.thread_id = t.id AND turn.rollout_ordinal = (
                SELECT max(rollout_ordinal) FROM history.thread_turns WHERE thread_id = t.id
            )
            LEFT JOIN history.thread_items item ON item.thread_id = t.id AND item.rollout_ordinal = (
                    SELECT rollout_ordinal FROM history.thread_items
                    WHERE thread_id = t.id AND turn_id = turn.turn_id AND item_type != 'reasoning'
                    ORDER BY updated_at_ordinal DESC, rollout_ordinal DESC LIMIT 1
                )
            WHERE t.id IN (SELECT id FROM recent) \(watchedFilter)
            """, bindings: ids) { row in
                let updated = Self.date(row, 4) ?? .distantPast
                let started = Self.date(row, 6)
                let activity = Self.date(row, 7)
                let label = Self.string(row, 2)
                let project = sqlite3_column_int(row, 3) == 1 ? label : URL(fileURLWithPath: label).lastPathComponent
                sessions.append(Session(
                    id: Self.string(row, 0), title: Self.title(Self.string(row, 1)), project: project.isEmpty ? "本地" : project,
                    updated: updated, activity: activity, started: started,
                    status: SessionStatus(Self.string(row, 5), activity: max(updated, activity ?? updated, started ?? updated), now: now),
                    lastAction: Self.activityLabel(Self.string(row, 8)),
                    acceptsMessages: sqlite3_column_int(row, 9) == 1
                ))
            }
        return sessions.sorted { $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate > $1.sortDate }
    }

    private func messages(for id: String) throws -> [SessionMessage] {
        var messages: [SessionMessage] = []
        try query("""
            SELECT item_id, item_type, created_at_ms,
                CASE WHEN item_type = 'agentMessage' THEN substr(json_extract(item_json, '$.text'), 1, 12000)
                     ELSE (
                         SELECT substr(group_concat(json_extract(value, '$.text'), char(10)), 1, 65536)
                         FROM json_each(item_json, '$.content')
                         WHERE json_extract(value, '$.type') = 'text'
                     ) END,
                json_extract(item_json, '$.phase'), turn_id
            FROM history.thread_items
            WHERE thread_id = ? AND item_type IN ('userMessage', 'agentMessage')
            ORDER BY rollout_ordinal DESC
            LIMIT 30
            """, bindings: [id]) { row in
                let kind: SessionMessage.Kind = switch Self.string(row, 1) {
                    case "userMessage": .userMessage
                    default: Self.string(row, 4) == "commentary" ? .progress : .result
                }
                let text = Self.string(row, 3).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, let date = Self.date(row, 2) else { return }
                messages.append(.init(id: Self.string(row, 0), turnID: Self.string(row, 5),
                                      kind: kind, date: date, text: text))
            }
        return messages.reversed()
    }

    private func query(_ sql: String, bindings: [String] = [], row: (OpaquePointer) -> Void = { _ in }) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError()
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), value, -1, Self.transient) == SQLITE_OK else {
                throw sqliteError()
            }
        }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            row(statement)
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw sqliteError() }
    }

    private func sqliteError() -> DatabaseError {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite"
        return DatabaseError(message: "读取 Codex 本地记录失败（\(detail)）。")
    }

    private static func string(_ row: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(row, column) else { return "" }
        return String(cString: value)
    }

    private static func date(_ row: OpaquePointer, _ column: Int32) -> Date? {
        let milliseconds = sqlite3_column_int64(row, column)
        guard milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    private static func title(_ value: String) -> String {
        let singleLine = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if singleLine.isEmpty { return "未命名会话" }
        if singleLine.count > 160 { return String(singleLine.prefix(159)) + "…" }
        return singleLine
    }

    private static func activityLabel(_ type: String) -> String? {
        switch type {
        case "commandExecution": "终端命令"
        case "fileChange": "文件变更"
        case "mcpToolCall", "dynamicToolCall", "webSearch": "工具调用"
        case "agentMessage": "Codex 消息"
        case "userMessage": "用户消息"
        case "plan": "计划更新"
        case "": nil
        default: "会话事件"
        }
    }
}

actor FeedReader {
    private let feed: CodexFeed

    init(directory: URL) {
        feed = CodexFeed(directory: directory)
    }

    func fetch(watching: Set<String>) throws -> FeedSnapshot {
        try feed.fetch(watching: watching)
    }
}
