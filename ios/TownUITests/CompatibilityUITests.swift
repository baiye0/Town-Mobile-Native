import XCTest

final class CompatibilityUITests: XCTestCase {
    private var app: XCUIApplication!
    private var server: LocalHistoryServer?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-glassEffects", "YES"]
        app.launch()
    }

    func testWelcomeAndConnectionSheet() {
        XCTAssertTrue(app.buttons["连接我的 Being"].waitForExistence(timeout: 15))
        app.buttons["连接我的 Being"].tap()
        XCTAssertTrue(app.secureTextFields["Being 完整连接地址"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["连接我的 Being"].waitForExistence(timeout: 5))
        capture("welcome")
    }

    override func tearDownWithError() throws {
        if let server {
            // Remove only the synthetic connection created by the scrolling test.
            if app.buttons["完成"].exists { app.buttons["完成"].tap() }
            app.tabBars.buttons["更多"].tap()
            let connection = app.staticTexts["连接 Being"]
            for _ in 0..<4 where !connection.isHittable { app.swipeUp() }
            if connection.isHittable {
                connection.tap()
                if app.staticTexts[server.endpoint].exists && app.buttons["断开连接"].exists {
                    app.buttons["断开连接"].tap()
                }
            }
            app.terminate()
            server.stop()
        }
    }

    func testDraftSurvivesSidebarAndTabNavigation() {
        // Multiline SwiftUI TextField is exposed as TextView on iOS 16.
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("compatibility draft")
        app.buttons["对话记录"].tap()
        XCTAssertTrue(app.buttons["收起侧栏"].waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)], timeout: 5)
        app.buttons["收起侧栏"].tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["收起侧栏"])], timeout: 5)
        app.tabBars.buttons["更多"].tap()
        XCTAssertTrue(app.navigationBars["更多"].waitForExistence(timeout: 5))
        app.tabBars.buttons["对话"].tap()
        XCTAssertEqual(input.value as? String, "compatibility draft")
        capture("draft-preserved")
    }

    func testEmptyStateNavigation() {
        app.tabBars.buttons["围炉"].tap()
        XCTAssertTrue(app.staticTexts["连接 Town，继续阅读"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["配置 Town 连接"].exists)
        capture("empty-state")
        app.tabBars.buttons["更多"].tap()
        let modelSettings = app.staticTexts["模型设置"]
        for _ in 0..<4 where !modelSettings.isHittable { app.swipeUp() }
        XCTAssertTrue(modelSettings.isHittable)
        modelSettings.tap()
        XCTAssertTrue(app.staticTexts["请先连接 Being 对话。"].waitForExistence(timeout: 5))
        capture("model-empty-state")
    }

    func testZHistoryReadingPositionAndReturnToBottom() throws {
        let ready = expectation(description: "Local history fixture is listening")
        let server = try LocalHistoryServer(ready: ready)
        self.server = server
        wait(for: [ready], timeout: 5)
        app.terminate()
        app.launchArguments += ["-scene.all.\(server.endpoint)", "YES"]
        app.launch()
        app.buttons["连接我的 Being"].tap()
        let link = app.secureTextFields["Being 完整连接地址"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText(server.endpoint + "?token=fixture")
        app.collectionViews.buttons["连接 Being"].tap()
        let last = app.staticTexts["Compatibility message 060"]
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        XCTAssertTrue(last.isHittable)
        app.scrollViews.firstMatch.swipeDown()
        app.scrollViews.firstMatch.swipeDown()
        let bottom = app.buttons["回到底部"]
        XCTAssertTrue(bottom.waitForExistence(timeout: 5))

        let received = expectation(description: "Updated history requested")
        server.appendMessage(received: received)
        app.buttons["刷新"].tap()
        wait(for: [received], timeout: 10)
        XCTAssertTrue(bottom.exists)
        XCTAssertFalse(app.staticTexts["Compatibility message 061"].isHittable)
        capture("history-reading-position")
        bottom.tap()
        XCTAssertTrue(app.staticTexts["Compatibility message 061"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Compatibility message 061"].isHittable)
        capture("history-bottom")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
