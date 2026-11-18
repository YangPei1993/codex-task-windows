import AppKit
import Foundation
import SQLite3
import XCTest
@testable import TaskWindows

final class ProcessAndComposerTests: XCTestCase {
    func testReturnRespectsCompositionAndMultilineEditing() {
        func action(_ flags: NSEvent.ModifierFlags = [], key: UInt16 = 36,
                    composing: Bool = false, repeating: Bool = false) -> ComposerReturnAction {
            .resolve(keyCode: key, modifiers: flags, composing: composing, repeating: repeating)
        }
        XCTAssertEqual(action(), .send)
        XCTAssertEqual(action(.command, key: 76), .send)
        XCTAssertEqual(action(.shift), .newline)
        XCTAssertEqual(action(composing: true), .system)
        XCTAssertEqual(action(.command, composing: true), .system)
        XCTAssertEqual(action(.option), .system)
        XCTAssertEqual(action(key: 49), .system)
        XCTAssertEqual(action(repeating: true), .ignore)
    }

    func testProcessReadsOnlyPublishedSummaryAndSelectedTurn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try database(directory.appendingPathComponent("state_5.sqlite"), sql: "CREATE TABLE fixture (id TEXT)")
        try database(directory.appendingPathComponent("thread_history_1.sqlite"), sql: """
            CREATE TABLE thread_items (
                thread_id TEXT, turn_id TEXT, item_id TEXT, item_type TEXT, created_at_ms INTEGER,
                started_at_ms INTEGER, completed_at_ms INTEGER, rollout_ordinal INTEGER,
                updated_at_ordinal INTEGER, item_json TEXT
            );
            INSERT INTO thread_items VALUES
            ('chat','turn','hidden','reasoning',1000,NULL,NULL,1,1,'{"summary":[],"content":["internal"]}'),
            ('chat','turn','public','reasoning',2000,NULL,NULL,2,2,'{"summary":["公开摘要","检查完毕"],"content":["internal"]}'),
            ('chat','turn','plan','plan',3000,NULL,NULL,3,3,'{"text":"先验证更新"}'),
            ('chat','turn','command','commandExecution',4000,4000,5000,4,4,'{"status":"failed","command":"private input","aggregatedOutput":"private output"}'),
            ('chat','other','old','plan',6000,NULL,NULL,5,5,'{"text":"其他轮次"}');
            """)
        let result = try CodexFeed(directory: directory).activities(for: "chat", turnID: "turn")
        XCTAssertEqual(result.map(\.id), ["public", "plan", "command"])
        XCTAssertEqual(result.map(\.text), ["公开摘要\n\n检查完毕", "先验证更新", nil])
        XCTAssertEqual(result.last?.state, .failed)
        XCTAssertEqual(result.last?.date, Date(timeIntervalSince1970: 5))
    }

    func testQuestionsRemainVisibleBeyondRecentMessageLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try database(directory.appendingPathComponent("state_5.sqlite"), sql: "CREATE TABLE fixture (id TEXT)")
        try database(directory.appendingPathComponent("thread_history_1.sqlite"), sql: """
            CREATE TABLE thread_turns (
                thread_id TEXT, turn_id TEXT, rollout_ordinal INTEGER, root_turn_id TEXT, first_user_item_id TEXT
            );
            CREATE TABLE thread_items (
                thread_id TEXT, turn_id TEXT, item_id TEXT, item_type TEXT,
                created_at_ms INTEGER, rollout_ordinal INTEGER, item_json TEXT
            );
            INSERT INTO thread_turns VALUES
            ('chat','direct',1,'root','question'),
            ('chat','unrelated',4,'other','wrong'),
            ('chat','continued',8,'root',NULL),
            ('chat','without-context',47,'untracked',NULL);
            INSERT INTO thread_items VALUES
            ('chat','direct','question','userMessage',1000,2,'{"content":[{"type":"text","text":"原始提问"}]}'),
            ('chat','unrelated','wrong','userMessage',2000,5,'{"content":[{"type":"text","text":"无关提问"}]}'),
            ('chat','continued','answer','agentMessage',46000,46,'{"phase":"final_answer","text":"对应回复"}'),
            ('chat','without-context','other-answer','agentMessage',48000,48,'{"phase":"final_answer","text":"另一条回复"}');
            WITH RECURSIVE steps(n) AS (SELECT 10 UNION ALL SELECT n + 1 FROM steps WHERE n < 45)
            INSERT INTO thread_items
            SELECT 'chat','continued','step-' || n,'agentMessage',n * 1000,n,'{"phase":"commentary","text":"过程进度"}'
            FROM steps;
            """)
        let feed = CodexFeed(directory: directory)
        let continued = try feed.messages(for: "chat", currentTurnID: "continued")
        XCTAssertEqual(continued.first?.id, "question")
        XCTAssertEqual(continued.first?.questionContext, .related)
        XCTAssertTrue(continued.contains { $0.id == "answer" && $0.turnID == "continued" })
        XCTAssertFalse(continued.contains { $0.id == "wrong" })

        let direct = try feed.messages(for: "chat", currentTurnID: "direct")
        XCTAssertEqual(direct.first?.text, "原始提问")
        XCTAssertNil(direct.first?.questionContext)

        let withoutContext = try feed.messages(for: "chat", currentTurnID: "without-context")
        XCTAssertEqual(withoutContext.first?.id, "wrong")
        XCTAssertEqual(withoutContext.first?.questionContext, .previous)
        XCTAssertEqual(withoutContext.last?.id, "other-answer")
    }

    func testRepeatedOutgoingMessagesReconcileOneAtATime() {
        func userMessage(_ id: String, at time: TimeInterval) -> SessionMessage {
            .init(id: id, turnID: "turn", kind: .userMessage,
                  date: Date(timeIntervalSince1970: time), text: "再检查一次")
        }
        var outbox = SessionOutbox()
        let old = userMessage("old", at: 10.1)
        let first = outbox.submit("再检查一次", at: Date(timeIntervalSince1970: 10), knownMessages: [old])
        let second = outbox.submit("再检查一次", at: Date(timeIntervalSince1970: 10.05), knownMessages: [old])
        XCTAssertTrue(outbox.markQueued(first))
        XCTAssertTrue(outbox.markQueued(second))
        XCTAssertEqual(outbox.messages.map(\.phase), [.queued, .queued])

        let firstRecord = userMessage("first", at: 11)
        XCTAssertEqual(outbox.reconcile([old, firstRecord]), [first])
        XCTAssertEqual(outbox.messages.map(\.id), [second])
        XCTAssertEqual(outbox.reconcile([old, firstRecord]), [])
        XCTAssertEqual(outbox.reconcile([old, firstRecord, userMessage("second", at: 12)]), [second])
        XCTAssertTrue(outbox.messages.isEmpty)
    }

    private func database(_ url: URL, sql: String) throws {
        var db: OpaquePointer?
        let result = sqlite3_open(url.path, &db)
        defer { sqlite3_close(db) }
        guard result == SQLITE_OK, sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "ProcessFixture", code: Int(sqlite3_errcode(db)))
        }
    }
}
