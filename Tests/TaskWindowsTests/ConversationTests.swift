import Foundation
import XCTest
@testable import TaskWindows

final class ConversationTests: XCTestCase {
    func testReportSeparatesHeadingParagraphTableAndCode() throws {
        let document = MarkdownDocument("""
            ## 对账结果

            **通过**，查看[本地报告](/tmp/对账.md)和[外部文档](https://example.com)。

            | 报表 | 状态 |
            | :--- | ---: |
            | 出库 | **通过** |
            | 入库 | 待确认 |

            - 第一项
              - 子项

            ~~~sql
            SELECT 1;
            ~~~
            """)
        XCTAssertEqual(document.sections.count, 6)
        guard case .block(let heading) = document.sections[0],
              case .block(let paragraph) = document.sections[1],
              case .table(_, let table) = document.sections[2],
              case .block(let listItem) = document.sections[4],
              case .block(let code) = document.sections[5] else {
            return XCTFail("报表 Markdown 未按预期分块")
        }
        XCTAssertEqual(heading.kind, .header(level: 2))
        XCTAssertTrue(paragraph.text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertEqual(paragraph.text.runs.compactMap(\.link).map(\.scheme), ["file", "https"])
        XCTAssertEqual(table.columns.map(\.alignment), [.left, .right])
        XCTAssertEqual(table.rows.map(\.header), [true, false, false])
        XCTAssertEqual(table.rows[2].cells[1].map { String($0.characters) }, "待确认")
        XCTAssertEqual(listItem.ancestors.filter { $0.kind == .unorderedList }.count, 2)
        XCTAssertEqual(code.kind, .codeBlock(languageHint: "sql"))
    }

    func testQueuePreservesMessageAndRequiresReceiptForExactThread() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        let id = "01a00000-1234-7890-a000-000000000001"
        let otherID = "01a00000-1234-7890-a000-000000000002"
        // 模拟真实 CLI 的参数和回执，涵盖中文、多行和 shell 元字符。
        try """
            #!/bin/sh
            [ "$#" = 4 ] && [ "$1" = queue ] && [ "$2" = --thread ] || exit 2
            [ "$4" = '--message=--保留字面量 $(exit 55)
            第二行; echo "示例"' ] || exit 3
            printf 'Queued message sample for thread \(id).\\n'
            """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let message = "--保留字面量 $(exit 55)\n第二行; echo \"示例\""
        XCTAssertNoThrow(try CodexQueue.enqueue(message, threadID: id, executable: executable))
        XCTAssertThrowsError(try CodexQueue.enqueue(message, threadID: otherID, executable: executable)) {
            XCTAssertEqual($0 as? CodexQueue.SubmitError, .confirmationMissing)
        }
        XCTAssertThrowsError(try CodexQueue.enqueue("只含一行", threadID: id, executable: executable)) {
            XCTAssertEqual($0 as? CodexQueue.SubmitError, .rejected)
        }
    }
}
