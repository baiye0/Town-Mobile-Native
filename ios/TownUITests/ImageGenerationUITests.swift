import XCTest

/// Loopback history fixture; never submits a real generation or uses a user's connection.
final class ImageGenerationUITests: XCTestCase {
    func testStreamReceiptCardsAndHistoryRecovery() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Only run the synthetic receipt fixture on an isolated simulator")
        #endif
        continueAfterFailure = false
        let ready = expectation(description: "Loopback fixture")
        let server = try LocalHistoryServer(ready: ready)
        wait(for: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-glassEffects", "YES", "-scene.all.\(server.endpoint)", "YES"]
        app.launch()
        if !app.buttons["连接我的 Being"].exists {
            app.tabBars.buttons["更多"].tap()
            XCTAssertTrue(app.navigationBars["更多"].waitForExistence(timeout: 10))
            app.buttons["beingConnection"].tap()
            let fixture = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'http://127.0.0.1:'")).firstMatch
            XCTAssertTrue(fixture.waitForExistence(timeout: 5), "Only disconnect a previous loopback fixture")
            app.buttons["断开连接"].tap()
            app.terminate(); app.launch()
        }
        XCTAssertTrue(app.buttons["连接我的 Being"].waitForExistence(timeout: 10))
        app.buttons["连接我的 Being"].tap()
        let link = app.secureTextFields["Being 完整连接地址"]
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap(); link.typeText(server.endpoint + "?token=fixture")
        app.scrollViews.buttons["连接 Being"].tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: link)], timeout: 10)
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)], timeout: 5)
        server.enableChat(staged: true)
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap(); input.typeText("Receipt fixture")
        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["停止生成"].waitForExistence(timeout: 10))
        server.appendReply("图片任务说明\n\n```json\n{\"type\":\"being.image-generation\",")
        XCTAssertTrue(app.staticTexts["正在接收图片任务回执…"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["生成图片"].exists)
        server.appendReply("\"version\":1,\"being_id\":\"compat\",\"jobs\":[{\"index\":1,\"title\":\"蓝猫窗边\",\"submission\":\"accepted\",\"generation_id\":\"gen_fixture\",\"client_request_id\":\"cat-fixture\",\"error_code\":null}]}\n```\n\n回执后的说明")
        XCTAssertTrue(app.staticTexts["正在接收图片任务回执…"].exists)
        server.finishReply()
        XCTAssertTrue(app.staticTexts["生成图片"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 张"].exists)
        // Custom Heart credentials must never be sent to the production Gateway.
        XCTAssertTrue(app.staticTexts["回执与当前连接不匹配，或当前 Heart 未配置生图服务"].exists)
        XCTAssertTrue(app.staticTexts["回执后的说明"].exists)
        XCTAssertFalse(app.buttons["复制代码"].exists)
        XCTAssertFalse(app.buttons["重新查询"].exists)
        XCTAssertFalse(app.staticTexts["生成成功"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "image-generation-receipt-card"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["刷新"].tap()
        XCTAssertTrue(app.staticTexts["生成图片"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "1 张").count, 1)
        XCTAssertEqual(server.sentMessages, ["Receipt fixture"])
        app.terminate()
    }
}
