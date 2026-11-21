import XCTest
@testable import KnowledgeCore

final class LoungeTimeTests: XCTestCase {
    func testForegroundLedgerIgnoresBackgroundAndUsesMonotonicTime() {
        var ledger = LoungeLedger()
        let source = UUID()
        let start = Date(timeIntervalSince1970: 86_390)
        ledger.transition(active: true, sourceID: source, now: start, uptime: 10)
        ledger.transition(active: true, sourceID: source, now: start.addingTimeInterval(5), uptime: 15)
        ledger.checkpoint(now: start.addingTimeInterval(10), uptime: 20)
        ledger.transition(active: true, sourceID: nil, now: start.addingTimeInterval(20), uptime: 30)
        ledger.transition(active: false, sourceID: nil, now: start.addingTimeInterval(25), uptime: 35)
        XCTAssertEqual(ledger.snapshot(now: start.addingTimeInterval(400), uptime: 410).map(\.duration), [20, 5])
        XCTAssertEqual(ledger.records.map(\.sourceID), [source, nil])
        let midnight = Date(timeIntervalSince1970: 86_400)
        XCTAssertEqual(ledger.records[0].seconds(in: DateInterval(start: midnight, duration: 86_400)), 10)
    }

    func testCountdownSurvivesSerializationAndCompletionCanBeConsumedOnlyOnce() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        var timer = LoungeCountdown()
        timer.start(minutes: 15, at: now)
        timer.pause(at: now.addingTimeInterval(29))
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(500)), 871)
        timer.resume(at: now.addingTimeInterval(500))
        let data = try JSONEncoder().encode(timer)
        var reopened = try JSONDecoder().decode(LoungeCountdown.self, from: data)
        XCTAssertEqual(reopened.remaining(at: now.addingTimeInterval(501)), 870)
        XCTAssertTrue(reopened.consumeCompletion(at: now.addingTimeInterval(1_371)))
        XCTAssertFalse(reopened.consumeCompletion(at: now.addingTimeInterval(1_372)))
    }

    func testCSVAllowsQuotedSeparatorsAndMultilineValues() throws {
        let rows = try LoungeCSV.rows("标题,内容\r\n爵士,\"听一首歌, 或者\n看看窗外\"\n")
        XCTAssertEqual(rows, [["标题", "内容"], ["爵士", "听一首歌, 或者\n看看窗外"]])
        XCTAssertThrowsError(try LoungeCSV.rows("\"未闭合"))
    }
}
