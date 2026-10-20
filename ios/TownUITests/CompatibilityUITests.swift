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
            // Remove only the synthetic connection created by the test.
            if app.otherElements["cameraCapture"].exists {
                let cancel = app.buttons["DismissImagePickerButton"].exists ? app.buttons["DismissImagePickerButton"] : app.buttons["取消"]
                if cancel.exists { cancel.tap() }
            }
            server.finishReply()
            wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 10)
            if app.buttons["完成"].exists { app.buttons["完成"].tap() }
            if app.keyboards.firstMatch.exists {
                app.buttons["对话记录"].tap()
                XCTAssertTrue(app.buttons["收起侧栏"].waitForExistence(timeout: 5))
                app.buttons["收起侧栏"].tap()
                wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)], timeout: 5)
            }
            XCTAssertTrue(app.tabBars.buttons["更多"].isHittable)
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
        let server = try connectToFixture()
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

    func testFocusingComposerReturnsToBottomAndKeepsLatestAboveKeyboard() throws {
        _ = try connectToFixture()
        let last = app.staticTexts["Compatibility message 060"]
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        let messages = app.scrollViews["chatMessageList"]
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        browseEarlier()
        browseEarlier()
        XCTAssertTrue(app.buttons["回到底部"].waitForExistence(timeout: 5))
        XCTAssertFalse(last.isHittable)

        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        assertLatestVisible()
        input.typeText("line one\nline two\nline three\nline four")
        assertLatestVisible()
        capture("composer-focus-latest-above-keyboard")

        // Browsing history still takes precedence after the explicit focus jump.
        browseEarlier()
        browseEarlier()
        XCTAssertTrue(app.buttons["回到底部"].waitForExistence(timeout: 5))
        XCTAssertFalse(last.isHittable)
        app.buttons["对话记录"].tap()
        XCTAssertTrue(app.buttons["收起侧栏"].waitForExistence(timeout: 5))
        app.buttons["收起侧栏"].tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)], timeout: 5)
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        assertLatestVisible()
        XCTAssertEqual(input.value as? String, "line one\nline two\nline three\nline four")

        func browseEarlier() {
            // The accessibility scroll frame can extend behind navigation chrome.
            // Keep the drag below the toolbar and above the input/keyboard.
            let top = max(messages.frame.minY, app.navigationBars.firstMatch.frame.maxY)
            let height = min(messages.frame.maxY, input.frame.minY) - top
            let origin = messages.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: messages.frame.width / 2, dy: top - messages.frame.minY + height * 0.2))
            let end = origin.withOffset(CGVector(dx: messages.frame.width / 2, dy: top - messages.frame.minY + height * 0.8))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        func assertLatestVisible() {
            wait(for: [expectation(for: NSPredicate { _, _ in
                last.exists && last.isHittable && last.frame.maxY <= input.frame.minY && !self.app.buttons["回到底部"].exists
            }, evaluatedWith: nil)], timeout: 5)
        }
    }

    func testCameraOpensFullScreenAndCanReopenAfterCancel() throws {
        _ = try connectToFixture()
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        for attempt in 1...2 {
            app.buttons["展开资源库"].tap()
            XCTAssertTrue(app.buttons["拍照"].waitForExistence(timeout: 5))
            app.buttons["拍照"].tap()
            let camera = app.otherElements["cameraCapture"]
            XCTAssertTrue(camera.waitForExistence(timeout: 5))
            // Check the entire presentation, including the top and bottom safe areas.
            // Actual sensor capture still requires a physical device.
            let screen = app.windows.firstMatch.frame
            XCTAssertEqual(camera.frame.minY, screen.minY, accuracy: 1)
            XCTAssertEqual(camera.frame.maxY, screen.maxY, accuracy: 1)
            XCTAssertEqual(camera.frame.width, screen.width, accuracy: 1)
            capture("camera-fullscreen-\(attempt)")
            let cancel = app.buttons["DismissImagePickerButton"].exists ? app.buttons["DismissImagePickerButton"] : app.buttons["取消"]
            cancel.tap()
            wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: camera)], timeout: 5)
            XCTAssertTrue(app.buttons["展开资源库"].isHittable)
        }
    }

    func testLiveProcessAndIncrementalReplyBeforeStreamCompletes() throws {
        let server = try connectToFixture()
        server.enableChat(staged: true)
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap(); input.typeText("Incremental reply prompt")
        app.buttons["发送"].tap()
        let preview = app.staticTexts["liveProcessPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.label.contains("正在检查上下文"))
        XCTAssertFalse(app.staticTexts["第一段"].exists)
        // History acknowledges the prompt before the run or reply is complete.
        app.buttons["刷新"].tap()
        server.emitProgress("reasoning", ["delta": "，继续核对信息"])
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", "继续核对信息"), evaluatedWith: preview)], timeout: 5)
        server.emitProgress("tool_use", ["name": "search", "input": ["query": "fixture"]])
        XCTAssertTrue(app.buttons["activeRunDetails"].waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", "search"), evaluatedWith: app.buttons["activeRunDetails"])], timeout: 5)
        app.buttons["activeRunDetails"].tap()
        XCTAssertTrue(app.staticTexts["runProcessDetails"].label.contains("继续核对信息"))
        app.buttons["activeRunDetails"].tap()
        server.emitProgress("tool_result", ["content": "已找到结果"])
        server.appendReply("第一段")
        let first = app.staticTexts["第一段"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["停止生成"].exists)
        capture("incremental-first-fragment")
        // Release each chunk only AFTER observing the previous chunk in the UI.
        // A final-only render cannot pass this test, regardless of network speed.
        server.appendReply("，第二段")
        let second = app.staticTexts["第一段，第二段"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["停止生成"].exists)
        server.appendReply("，第三段。")
        let complete = app.staticTexts["第一段，第二段，第三段。"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["停止生成"].exists)
        server.finishReply()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 10)
        let details = app.buttons["completedRunDetails"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertEqual(details.value as? String, "已折叠")
        XCTAssertLessThan(app.staticTexts["Incremental reply prompt"].frame.minY, details.frame.minY)
        XCTAssertLessThan(details.frame.minY, complete.frame.minY)
        XCTAssertEqual(app.staticTexts.matching(identifier: "第一段，第二段，第三段。").count, 1)
        details.tap()
        XCTAssertTrue(app.staticTexts["runProcessDetails"].label.contains("已找到结果"))
        capture("incremental-completed-process")
    }

    func testStreamingOrderDraftAndReplyBoundaries() throws {
        let server = try connectToFixture()
        server.enableChat()
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap(); input.typeText("Order regression prompt")
        app.buttons["发送"].tap()
        let first = app.staticTexts["First streamed reply."]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        // History now confirms only the user, while the reply is still streaming.
        app.buttons["刷新"].tap()
        let prompt = app.staticTexts["Order regression prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertLessThan(prompt.frame.minY, first.frame.minY)
        XCTAssertFalse(app.staticTexts["正在发送"].exists)
        input.tap(); input.typeText("draft during streaming")
        XCTAssertEqual(input.value as? String, "draft during streaming")
        XCTAssertTrue(app.buttons["立即发送"].exists)
        XCTAssertTrue(app.buttons["加入队列"].exists)
        server.nextReply()
        let second = app.staticTexts["Second streamed reply."]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        server.finishReply()
        XCTAssertTrue(app.buttons["发送"].waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "draft during streaming")
        first.tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)], timeout: 5)
        XCTAssertEqual(app.staticTexts.matching(identifier: "First streamed reply.").count, 1)
        XCTAssertLessThan(prompt.frame.minY, first.frame.minY)
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        XCTAssertEqual(server.sentMessages, ["Order regression prompt"])
        capture("stream-order-and-composer")
    }

    func testLongStreamingReplyKeepsItsBeginningVisible() throws {
        let server = try connectToFixture()
        server.enableChat()
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap(); input.typeText("Long reply fixture")
        app.buttons["发送"].tap()
        let first = app.staticTexts["First streamed reply."]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)], timeout: 5)
        server.appendReply(String(repeating: "\n\nStreaming detail.", count: 30))
        XCTAssertTrue(app.buttons["回到底部"].waitForExistence(timeout: 10))
        XCTAssertTrue(first.isHittable)
        let top = first.frame.minY
        server.appendReply("\n\nTail after more streaming.")
        // The tail exists in the document but must not pull the reading anchor.
        XCTAssertTrue(app.staticTexts["Tail after more streaming."].waitForExistence(timeout: 10))
        XCTAssertEqual(first.frame.minY, top, accuracy: 5)
        capture("long-reply-reading-anchor")
        server.finishReply()
        XCTAssertTrue(app.buttons["展开资源库"].exists)
    }

    func testPrioritySendStopsCurrentTurnAndDrainsQueueInOrder() throws {
        let server = try connectToFixture()
        server.enableChat()
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap(); input.typeText("first turn")
        app.buttons["发送"].tap()
        XCTAssertTrue(app.staticTexts["First streamed reply."].waitForExistence(timeout: 10))
        input.tap(); input.typeText("queued turn")
        app.buttons["加入队列"].tap()
        input.tap(); input.typeText("priority turn")
        app.buttons["立即发送"].tap()
        wait(for: [expectation(for: NSPredicate { _, _ in
            server.sentMessages == ["first turn", "priority turn"]
        }, evaluatedWith: nil)], timeout: 10)
        server.finishReply()
        wait(for: [expectation(for: NSPredicate { _, _ in
            server.sentMessages == ["first turn", "priority turn", "queued turn"]
        }, evaluatedWith: nil)], timeout: 10)
        server.finishReply()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 10)
    }

    private func connectToFixture() throws -> LocalHistoryServer {
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
        // History may appear behind the closing sheet before its keyboard has
        // relinquished focus. Wait for the actual presentation to complete.
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: link)], timeout: 10)
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)], timeout: 5)
        return server
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
