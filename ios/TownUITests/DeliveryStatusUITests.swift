import XCTest

final class DeliveryStatusUITests: XCTestCase {
    func testFailureIconRetryAndUnconfirmedSendDoesNotBlockLaterMessages() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Delivery fixtures only run on an isolated simulator")
        #endif
        continueAfterFailure = false
        let ready = expectation(description: "Loopback delivery fixture")
        let server = try LocalHistoryServer(ready: ready)
        defer { server.stop() }
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
        server.enableChat()
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        let retry = app.buttons["retryMessage"]
        func send(_ text: String) { input.tap(); input.typeText(text); app.buttons["发送"].tap() }
        func sent(_ count: Int) {
            wait(for: [expectation(for: NSPredicate { _, _ in server.sentMessages.count == count }, evaluatedWith: nil)], timeout: 12)
        }
        func finished() {
            server.finishReply()
            wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 12)
        }
        func retryFromDetails() {
            retry.tap()
            XCTAssertTrue(app.staticTexts["deliveryFailureReason"].waitForExistence(timeout: 5))
            app.buttons["confirmRetryMessage"].tap()
        }
        server.failNextChat(status: 400)
        send("Failed message")
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        XCTAssertFalse(app.staticTexts["发送失败"].exists)
        XCTAssertFalse(app.staticTexts["排队中"].exists)
        XCTAssertFalse(app.buttons["核对历史"].exists)
        XCTAssertLessThan(retry.frame.maxX, app.staticTexts["Failed message"].frame.minX)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "delivery-red-retry-icon"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(app.buttons["deliveryFailureSummary"].exists)
        retry.tap()
        let reason = app.staticTexts["deliveryFailureReason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertTrue(reason.label.contains("HTTP 400"))
        XCTAssertTrue(reason.label.contains("发送消息失败"))
        app.buttons["copyDeliveryFailure"].tap()
        XCTAssertTrue(app.buttons["已复制错误信息"].exists)
        XCTAssertEqual(server.sentMessages.count, 1, "Reading and copying details must not resend")
        let detailCapture = XCTAttachment(screenshot: app.screenshot())
        detailCapture.name = "delivery-failure-details"; detailCapture.lifetime = .keepAlways; add(detailCapture)
        app.buttons["confirmRetryMessage"].tap(); sent(2); finished()
        XCTAssertFalse(retry.exists)

        server.failNextChat(status: 503)
        send("Unconfirmed message")
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        send("Next message")
        sent(4)
        XCTAssertEqual(server.sentMessages.last, "Next message")
        XCTAssertFalse(app.staticTexts["排队中"].exists)
        finished()
        // Scroll back to the failed message if the successful reply moved it off screen.
        for _ in 0..<4 where !retry.isHittable { app.swipeDown() }
        XCTAssertTrue(retry.isHittable); retryFromDetails(); sent(5)
        XCTAssertEqual(server.sentMessages.last, "Unconfirmed message")
        finished()
        XCTAssertFalse(retry.exists)

        server.failNextChat(status: 503, persistUser: true)
        send("Accepted message")
        XCTAssertTrue(retry.waitForExistence(timeout: 12)); sent(6)
        retryFromDetails()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: retry)], timeout: 12)
        XCTAssertEqual(server.sentMessages.count, 6, "A server-confirmed submission must not be posted twice")
        server.failNextChat(status: 503, persistUser: true)
        send("Accepted streaming message")
        XCTAssertTrue(retry.waitForExistence(timeout: 12)); sent(7)
        server.resumeAcceptedReplyAsReplay()
        retryFromDetails()
        server.appendReply("恢复后第一段")
        XCTAssertTrue(app.staticTexts["恢复后第一段"].waitForExistence(timeout: 12))
        server.appendReply("，继续显示第二段。")
        XCTAssertTrue(app.staticTexts["恢复后第一段，继续显示第二段。"].waitForExistence(timeout: 12))
        finished()
        XCTAssertEqual(server.sentMessages.count, 7, "Recovery must only read the existing stream")
        app.terminate()
    }
}
