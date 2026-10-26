import XCTest

final class PortalUITests: XCTestCase {
    func testPortalEntryWithoutConnectionAndPermissionLayout() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        if !app.buttons["连接我的 Being"].exists {
            app.tabBars.buttons["更多"].tap()
            app.buttons["beingConnection"].tap()
            let fixture = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'http://127.0.0.1:'")).firstMatch
            XCTAssertTrue(fixture.waitForExistence(timeout: 5), "Only disconnect an isolated loopback fixture")
            app.buttons["断开连接"].tap()
            app.terminate(); app.launch()
        }
        let more = app.tabBars.buttons["更多"]
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        let entry = app.buttons.containing(.staticText, identifier: "本机 Portal").firstMatch
        for _ in 0..<3 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.navigationBars["本机 Portal"].waitForExistence(timeout: 5))
        let start = app.buttons["portalStartStop"]
        XCTAssertTrue(start.exists)
        XCTAssertFalse(start.isEnabled)
        XCTAssertEqual(app.staticTexts["portalStatus"].label, "尚未启动")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "ios-portal-overview"; attachment.lifetime = .keepAlways; add(attachment)
        for _ in 0..<5 where !app.staticTexts["文件工作区"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["文件工作区"].waitForExistence(timeout: 5))
        let workspace = XCTAttachment(screenshot: app.screenshot()); workspace.name = "ios-portal-workspace"; workspace.lifetime = .keepAlways; add(workspace)
    }
}
