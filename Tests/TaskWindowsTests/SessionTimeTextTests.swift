import XCTest
@testable import TaskWindows

final class SessionTimeTextTests: XCTestCase {
    func testElapsedTextScalesFromSecondsToHours() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Session.elapsedText(since: start, now: start.addingTimeInterval(45)), "45 秒")
        XCTAssertEqual(Session.elapsedText(since: start, now: start.addingTimeInterval(12 * 60 + 5)), "12 分")
        XCTAssertEqual(Session.elapsedText(since: start, now: start.addingTimeInterval(3600)), "1 小时")
        XCTAssertEqual(Session.elapsedText(since: start, now: start.addingTimeInterval(3900)), "1 小时 5 分")
        // 时钟回拨时不显示负数。
        XCTAssertEqual(Session.elapsedText(since: start, now: start.addingTimeInterval(-5)), "0 秒")
    }

    func testRelativeTextUsesRecentPhrasesWithinAnHour() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(Session.relativeText(now.addingTimeInterval(-3), now: now), "刚刚")
        XCTAssertEqual(Session.relativeText(now.addingTimeInterval(-30), now: now), "30 秒前")
        XCTAssertEqual(Session.relativeText(now.addingTimeInterval(-600), now: now), "10 分钟前")
        let old = now.addingTimeInterval(-7200)
        XCTAssertEqual(Session.relativeText(old, now: now), Session.friendlyTimestamp(old))
    }
}
