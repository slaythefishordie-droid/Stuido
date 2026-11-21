import XCTest

@MainActor
final class StudyAcceptanceTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ section: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["STUDIO_ACCEPTANCE_FIXTURE"] = UUID().uuidString
        app.launch()
        let rail = app.buttons["studio.nav." + section]
        XCTAssertTrue(rail.waitForExistence(timeout: 10))
        rail.tap()
        return app
    }

    func testInboxOpensPrefilledEditorThenArchivesInOneSave() {
        let app = launch("inbox")
        let organize = app.buttons["inbox.organize"]
        XCTAssertTrue(organize.waitForExistence(timeout: 5))
        organize.tap()
        let body = app.descendants(matching: .any).matching(identifier: "card.editor.main").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 4))
        XCTAssertEqual(body.value as? String, "模拟器摘录")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["撤销归档"].waitForExistence(timeout: 5))
        XCTAssertFalse(organize.exists)
        app.buttons["撤销归档"].tap()
        XCTAssertTrue(organize.waitForExistence(timeout: 4))
    }

    func testStorageMovesRestoresAndPermanentlyDeletesOnlySelectedObject() {
        let app = launch("manager")
        let removable = app.buttons["storage.actions.可移除资料"]
        let retained = app.buttons["storage.actions.来源样本"]
        XCTAssertTrue(removable.waitForExistence(timeout: 5))
        removable.tap()
        tap(app, "移入回收站")
        tap(app, "移入回收站")
        XCTAssertTrue(removable.waitForNonExistence(timeout: 5))
        XCTAssertTrue(retained.exists)

        tap(app, "回收站")
        XCTAssertTrue(removable.waitForExistence(timeout: 5))
        removable.tap()
        tap(app, "恢复")
        XCTAssertTrue(removable.waitForNonExistence(timeout: 5))

        tap(app, "知识库")
        XCTAssertTrue(removable.waitForExistence(timeout: 5))
        removable.tap()
        tap(app, "移入回收站")
        tap(app, "移入回收站")
        XCTAssertTrue(removable.waitForNonExistence(timeout: 5))
        tap(app, "回收站")
        XCTAssertTrue(removable.waitForExistence(timeout: 5))
        removable.tap()
        tap(app, "永久删除")
        tap(app, "永久删除")
        XCTAssertTrue(removable.waitForNonExistence(timeout: 5))
        tap(app, "知识库")
        XCTAssertTrue(retained.waitForExistence(timeout: 5))
    }

    func testReviewHidesContentUntilQueueThenAdvances() {
        let app = launch("today")
        let queue = app.buttons["review.queue.word"]
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["复习样本甲"].exists)
        XCTAssertFalse(app.staticTexts["复习样本乙"].exists)
        queue.tap()
        let rate = app.buttons["review.rate.3"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        let first = app.staticTexts["复习样本甲"].exists ? "复习样本甲" : "复习样本乙"
        let second = first == "复习样本甲" ? "复习样本乙" : "复习样本甲"
        XCTAssertTrue(app.staticTexts[first].exists)
        rate.tap()
        XCTAssertTrue(app.staticTexts[second].waitForExistence(timeout: 5))
        rate.tap()
        XCTAssertTrue(app.staticTexts["本轮结束"].waitForExistence(timeout: 5))
    }

    private func tap(_ app: XCUIApplication, _ label: String) {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "找不到按钮 \(label)")
        button.tap()
    }
}
