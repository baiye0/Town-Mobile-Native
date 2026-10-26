import XCTest
import UIKit

final class CompatibilityUITests: XCTestCase {
    private var app: XCUIApplication!
    private var server: LocalHistoryServer?
    private var expandedUI: XCUIElement { app.webViews["expandedIntelligentUI"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-glassEffects", "YES"]
        app.launch()
    }

    func testPortalConnectedConfigurationAndStop() throws {
        _ = try connectToFixture()
        app.tabBars.buttons["更多"].tap()
        let entry = app.buttons.containing(.staticText, identifier: "本机 Portal").firstMatch
        for _ in 0..<3 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        let start = app.buttons["portalStartStop"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertTrue(app.buttons["停止 Portal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["portalName"].isEnabled)
        app.buttons["停止 Portal"].tap()
        XCTAssertEqual(app.staticTexts["portalStatus"].label, "尚未启动")
        let expand = app.buttons["portalPermissions"]
        for _ in 0..<3 where !expand.isHittable { app.swipeUp() }
        expand.tap()
        XCTAssertTrue(app.switches["允许读取"].firstMatch.waitForExistence(timeout: 5))
        capture("ios-portal-permissions")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["beingConnection"].waitForExistence(timeout: 5))
    }

    func testPortalDeniedCalendarAndHealthControls() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Permission UI fixtures only run on an isolated simulator")
        #endif
        app.resetAuthorizationStatus(for: .calendar)
        app.resetAuthorizationStatus(for: .health)
        app.launch()
        _ = try connectToFixture()
        app.tabBars.buttons["更多"].tap()
        let entry = app.buttons.containing(.staticText, identifier: "本机 Portal").firstMatch
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        let expand = app.buttons["portalPermissions"]
        for _ in 0..<4 where !expand.isHittable { app.swipeUp() }
        expand.tap()
        let toggle = app.switches["允许读取"].firstMatch
        for _ in 0..<3 where !toggle.isHittable { app.swipeUp() }
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        let deny = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS %@", "Don't Allow", "不允许")).firstMatch
        XCTAssertTrue(deny.exists)
        deny.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(app.buttons["前往系统设置授权"].firstMatch.exists)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
        capture("ios-portal-denied-permission")
        for _ in 0..<6 where !expand.isHittable { app.swipeDown() }
        expand.tap()
        let health = app.buttons["portalHealthConnect"]
        for _ in 0..<5 where !health.isHittable { app.swipeUp() }
        XCTAssertTrue(health.isEnabled)
        XCTAssertEqual(app.staticTexts["portalHealthStatus"].label, "尚未关联")
        capture("ios-portal-health-connect")
        health.tap()
        let proceed = app.buttons["portalHealthContinue"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 5))
        capture("ios-portal-health-introduction")
        app.buttons["portalHealthCancel"].tap()
        XCTAssertEqual(app.staticTexts["portalHealthStatus"].label, "尚未关联")
        health.tap()
        XCTAssertTrue(proceed.waitForExistence(timeout: 5))
        proceed.tap()
        let denyHealth = app.buttons["UIA.Health.DoNotAllow.Button"]
        XCTAssertTrue(denyHealth.waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["UIA.Health.步数.SwitchCell.Switch"].exists)
        capture("ios-portal-health-system-sheet")
        denyHealth.tap()
        let acknowledgement = app.buttons["好"]
        if acknowledgement.waitForExistence(timeout: 2) { acknowledgement.tap() }
        // Both completion and cancellation must leave a visible outcome in the sheet.
        let done = app.buttons["portalHealthDone"]
        let failed = app.staticTexts["Apple 健康关联未完成，请重试。"]
        let outcome = NSPredicate { _, _ in done.exists || failed.exists }
        wait(for: [expectation(for: outcome, evaluatedWith: app)], timeout: 8)
        capture("ios-portal-health-denied-result")
        if done.exists { done.tap() } else { app.buttons["portalHealthCancel"].tap() }
        XCTAssertTrue(app.staticTexts["portalHealthStatus"].waitForExistence(timeout: 5))
        // HealthKit does not reveal read denial. A connection must never claim
        // that the system has granted access to the requested categories.
        if app.buttons["portalHealthDisconnect"].exists {
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "iOS 不向 App 透露每类数据是否允许读取")).firstMatch.exists)
            app.buttons["portalHealthDisconnect"].tap()
        }
        XCTAssertEqual(app.staticTexts["portalHealthStatus"].label, "尚未关联")
        app.navigationBars.buttons.firstMatch.tap()
    }

    func testPortalHealthSuccessfulConnection() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("HealthKit UI fixtures only run on an isolated simulator")
        #endif
        app.resetAuthorizationStatus(for: .health)
        app.launch()
        _ = try connectToFixture()
        app.tabBars.buttons["更多"].tap()
        let entry = app.buttons.containing(.staticText, identifier: "本机 Portal").firstMatch
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        let health = app.buttons["portalHealthConnect"]
        for _ in 0..<5 where !health.isHittable { app.swipeUp() }
        health.tap()
        let proceed = app.buttons["portalHealthContinue"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 5)); proceed.tap()
        let all = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        XCTAssertTrue(all.waitForExistence(timeout: 10)); all.tap()
        let allow = app.buttons["UIA.Health.Allow.Button"]
        XCTAssertTrue(allow.isEnabled); allow.tap()
        let done = app.buttons["portalHealthDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["关联请求已完成"].exists)
        capture("ios-portal-health-completion")
        done.tap()
        XCTAssertEqual(app.staticTexts["portalHealthStatus"].label, "已关联当前 Being")
        // Repeating the same request may return immediately without a native sheet.
        app.buttons["管理健康关联与共享范围"].tap()
        XCTAssertTrue(proceed.waitForExistence(timeout: 5)); proceed.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["没有出现系统选择页？"].exists)
        capture("ios-portal-health-repeat-completion")
        done.tap()
        capture("ios-portal-health-connected")
        let disconnect = app.buttons["portalHealthDisconnect"]
        for _ in 0..<3 where !disconnect.isHittable { app.swipeUp() }
        disconnect.tap()
        XCTAssertEqual(app.staticTexts["portalHealthStatus"].label, "尚未关联")
        app.navigationBars.buttons.firstMatch.tap()
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
            for _ in 0..<3 {
                let done = app.buttons.matching(identifier: "完成").allElementsBoundByIndex.first(where: { $0.isHittable })
                guard let done else { break }
                done.tap()
            }
            if app.keyboards.firstMatch.exists {
                app.buttons["对话记录"].tap()
                XCTAssertTrue(app.buttons["收起侧栏"].waitForExistence(timeout: 5))
                app.buttons["收起侧栏"].tap()
                wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)], timeout: 5)
            }
            XCTAssertTrue(app.tabBars.buttons["更多"].isHittable)
            app.tabBars.buttons["更多"].tap()
            let connection = app.buttons["beingConnection"]
            for _ in 0..<4 where !connection.isHittable { app.swipeDown() }
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

    func testSidebarCloseHidesContentAndDismissesSearchKeyboard() {
        for _ in 0..<3 {
            app.buttons["对话记录"].tap()
            XCTAssertTrue(app.buttons["收起侧栏"].waitForExistence(timeout: 5))
            let search = app.textFields["搜索场景"]
            search.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            app.buttons["收起侧栏"].tap()
            wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["收起侧栏"])], timeout: 5)
            wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)], timeout: 5)
            XCTAssertTrue(app.buttons["对话记录"].waitForExistence(timeout: 5))
        }
        capture("sidebar-closed")
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

    func testSettingsSectionsAndAppearance() {
        app.tabBars.buttons["更多"].tap()
        XCTAssertTrue(app.buttons["beingConnection"].waitForExistence(timeout: 5))
        capture("settings-overview")
        app.buttons["beingConnection"].tap()
        XCTAssertTrue(app.secureTextFields["Being 完整连接地址"].waitForExistence(timeout: 5))
        capture("settings-connection")
        app.navigationBars.buttons.firstMatch.tap()

        app.staticTexts["对话设置"].tap()
        XCTAssertTrue(app.steppers.firstMatch.waitForExistence(timeout: 5))
        capture("settings-conversation")
        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["通知设置"].tap()
        XCTAssertTrue(app.switches["小镇通知总开关"].waitForExistence(timeout: 5))
        capture("settings-notifications")
        app.navigationBars.buttons.firstMatch.tap()

        app.staticTexts["外观"].tap()
        XCTAssertTrue(app.buttons["深色"].waitForExistence(timeout: 5))
        app.buttons["深色"].tap()
        capture("settings-appearance-dark")
        app.navigationBars.buttons.firstMatch.tap()
        capture("settings-overview-dark")
        app.staticTexts["外观"].tap()
        app.buttons["跟随系统"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        let navigation = app.staticTexts["底部导航"]
        for _ in 0..<3 where !navigation.isHittable { app.swipeUp() }
        navigation.tap()
        XCTAssertTrue(app.staticTexts["可添加"].waitForExistence(timeout: 5))
        capture("settings-navigation")
        app.navigationBars.buttons.firstMatch.tap()
        let pairing = app.staticTexts["小镇连接"]
        for _ in 0..<3 where !pairing.isHittable { app.swipeUp() }
        pairing.tap()
        XCTAssertTrue(app.buttons["自动连接 Town"].waitForExistence(timeout: 5))
        capture("settings-town-connection")
        app.navigationBars.buttons.firstMatch.tap()
        let square = app.staticTexts["小镇广场"]
        for _ in 0..<5 where !square.isHittable { app.swipeUp() }
        XCTAssertTrue(square.isHittable)
        capture("settings-town-grid")
    }

    func testSettingsWithSolidNavigationAndLargeText() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-glassEffects", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        app.buttons["更多"].tap()
        XCTAssertTrue(app.buttons["beingConnection"].waitForExistence(timeout: 5))
        capture("settings-large-text-solid")
        let appearance = app.staticTexts["外观"]
        for _ in 0..<5 where !appearance.isHittable { app.swipeUp() }
        appearance.tap()
        XCTAssertTrue(app.buttons["跟随系统"].waitForExistence(timeout: 5))
        capture("settings-appearance-large-text")
        app.buttons["返回"].tap()
        let town = app.staticTexts["小镇连接"]
        for _ in 0..<5 where !town.isHittable { app.swipeUp() }
        app.swipeUp()
        capture("settings-town-large-text")
        app.buttons["对话"].tap()
        XCTAssertTrue(app.buttons["连接我的 Being"].waitForExistence(timeout: 5))
    }

    func testSocialFeedLayoutAndFilters() {
        app.terminate()
        app.launchArguments += ["--social-layout-fixture"]
        app.launch()
        app.tabBars.buttons["篝火"].tap()
        XCTAssertTrue(app.staticTexts["林间"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["筛选当前已加载消息"].exists)
        XCTAssertFalse(app.staticTexts["读取数量"].exists)
        XCTAssertTrue(app.buttons["announcementStrip"].waitForExistence(timeout: 5))
        capture("social-bonfire")
        app.buttons["搜索与筛选"].tap()
        XCTAssertTrue(app.textFields["作者名称或 ID"].waitForExistence(timeout: 5))
        capture("social-filters")
        app.buttons["我发送的"].tap()
        app.buttons["查看结果"].tap()
        XCTAssertTrue(app.staticTexts["布局预览"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["林间"].exists)
        app.buttons["展开全文"].tap()
        capture("social-expanded-message")
        app.buttons["搜索与筛选"].tap()
        app.buttons["重置"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["林间"].waitForExistence(timeout: 5))
        app.buttons["更多操作"].tap()
        XCTAssertTrue(app.buttons["小镇公告"].waitForExistence(timeout: 5))
        app.buttons["小镇公告"].tap()
        XCTAssertTrue(app.navigationBars["公告"].waitForExistence(timeout: 5))
        app.staticTexts["小镇的新一天：在这里分享发现与灵感"].tap()
        XCTAssertTrue(app.staticTexts["欢迎来到小镇。这里是用于检查布局的示例公告。"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["完成"].tap()

        app.tabBars.buttons["私信"].tap()
        XCTAssertTrue(app.buttons["收件箱"].waitForExistence(timeout: 5))
        app.buttons["收件箱"].tap()
        XCTAssertTrue(app.staticTexts["林间"].waitForExistence(timeout: 5))
        capture("social-mail")
        app.buttons["已发送"].tap()
        XCTAssertTrue(app.staticTexts["布局预览"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["林间"].exists)

        app.tabBars.buttons["围炉"].tap()
        XCTAssertTrue(app.staticTexts["花园里的慢慢聊"].waitForExistence(timeout: 5))
        capture("social-firesides")
        app.buttons["搜索围炉"].tap()
        app.textFields["围炉名称"].tap()
        app.textFields["围炉名称"].typeText("读书")
        app.buttons["完成"].tap()
        XCTAssertFalse(app.staticTexts["花园里的慢慢聊"].exists)
        app.staticTexts["深夜读书会"].tap()
        XCTAssertTrue(app.navigationBars["深夜读书会"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["林间"].waitForExistence(timeout: 5))
        capture("social-fireside-detail")
        app.buttons["更多操作"].tap()
        XCTAssertTrue(app.buttons["围炉成员"].waitForExistence(timeout: 5))
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
        XCTAssertFalse(app.otherElements["messageSending"].exists)
        XCTAssertFalse(app.activityIndicators["messageSending"].exists)
        let activeDetails = app.buttons["activeRunDetails"]
        XCTAssertTrue(activeDetails.waitForExistence(timeout: 10))
        XCTAssertEqual(activeDetails.value as? String, "已折叠")
        XCTAssertFalse(app.staticTexts["liveProcessPreview"].exists)
        XCTAssertFalse(app.staticTexts["runProcessDetails"].exists)
        XCTAssertFalse(app.staticTexts["第一段"].exists)
        // History acknowledges the prompt before the run or reply is complete.
        app.buttons["刷新"].tap()
        server.emitProgress("reasoning", ["delta": "，继续核对信息"])
        XCTAssertFalse(app.staticTexts["runProcessDetails"].exists)
        server.emitProgress("tool_use", ["name": "search", "input": ["query": "fixture"]])
        XCTAssertTrue(app.buttons["activeRunDetails"].waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", "search"), evaluatedWith: app.buttons["activeRunDetails"])], timeout: 5)
        app.buttons["activeRunDetails"].tap()
        XCTAssertTrue(app.staticTexts["runProcessDetails"].label.contains("继续核对信息"))
        app.buttons["activeRunDetails"].tap()
        XCTAssertFalse(app.staticTexts["runProcessDetails"].exists)
        XCTAssertFalse(app.staticTexts["liveProcessPreview"].exists)
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

    func testHistoryAheadOfLiveReplyNeverAddsASecondBubble() throws {
        let server = try connectToFixture()
        server.enableChat(staged: true)
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap(); input.typeText("History ahead prompt"); app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["停止生成"].waitForExistence(timeout: 10))
        server.appendReply("第一段")
        XCTAssertTrue(app.staticTexts["第一段"].waitForExistence(timeout: 5))
        server.publishHistoryAhead("第一段，第二段，最终内容。")
        app.buttons["刷新"].tap()
        // Wait for the history read to finish before inspecting the race.
        wait(for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["刷新"])], timeout: 10)
        XCTAssertFalse(app.staticTexts["第一段，第二段，最终内容。"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "第一段").count, 1)
        server.appendReply("，第二段")
        XCTAssertTrue(app.staticTexts["第一段，第二段"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["第一段，第二段，最终内容。"].exists)
        server.appendReply("，最终内容。")
        XCTAssertTrue(app.staticTexts["第一段，第二段，最终内容。"].waitForExistence(timeout: 5))
        server.finishReply()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 10)
        app.buttons["刷新"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "第一段，第二段，最终内容。").count, 1)
        capture("single-live-reply-after-history-race")
    }

    func testQueuedReplyPublishesReplayFragmentsBeforeCompletion() throws {
        let server = try connectToFixture()
        server.enableReplayChat()
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap(); input.typeText("Replay incremental prompt")
        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["停止生成"].waitForExistence(timeout: 10))
        var reply = ""
        for part in ["收到", "一个", "片段", "就显示", "，不等", "全部完成。"] {
            server.appendReply(part)
            reply += part
            XCTAssertTrue(app.staticTexts[reply].waitForExistence(timeout: 4))
            XCTAssertTrue(app.buttons["停止生成"].exists)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "messageSending").firstMatch.exists)
        }
        server.finishReply()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 10)
        XCTAssertEqual(app.staticTexts.matching(identifier: reply).count, 1)
        XCTAssertEqual(server.sentMessages, ["Replay incremental prompt"])
        capture("replay-incremental-reply")
    }

    func testMarkdownImageStreamingRetryPreviewAndHistory() throws {
        let server = try connectToFixture()
        server.enableChat(staged: true)
        XCTAssertTrue(app.staticTexts["Compatibility message 060"].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap(); input.typeText("Markdown image fixture")
        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["停止生成"].waitForExistence(timeout: 10))
        server.appendReply("**图片预览**\n\n![测试图片](" + server.imageURL)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "![测试图片]")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["markdownImage"].exists)
        server.appendReply(")\n\n图片后的说明。")
        let retry = app.buttons["重试图片：测试图片"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        retry.tap()
        let image = app.buttons["查看图片：测试图片"]
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        server.finishReply()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 10)
        image.tap()
        XCTAssertTrue(app.navigationBars["测试图片"].waitForExistence(timeout: 5))
        let canvas = app.descendants(matching: .any).matching(identifier: "imagePreviewCanvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.doubleTap()
        XCTAssertTrue(app.buttons["适合屏幕"].waitForExistence(timeout: 5))
        app.buttons["适合屏幕"].tap()
        XCTAssertTrue(app.buttons["放大图片"].waitForExistence(timeout: 5))
        canvas.pinch(withScale: 2, velocity: 1)
        XCTAssertTrue(app.buttons["适合屏幕"].waitForExistence(timeout: 5))
        capture("markdown-image-zoomed")
        app.buttons["保存或分享图片"].tap()
        XCTAssertTrue(app.buttons["保存到文件"].waitForExistence(timeout: 5))
        app.buttons["保存到文件"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 10))
        capture("markdown-image-file-export")
        app.buttons["保存"].tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["保存"])], timeout: 10)
        app.buttons["保存或分享图片"].tap()
        app.buttons["保存到相册"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3) {
            let allow = springboard.alerts.buttons.matching(NSPredicate(format: "(label CONTAINS '允许' OR label CONTAINS 'Allow') AND NOT label CONTAINS '不' AND NOT label CONTAINS 'Don'" )).firstMatch
            if allow.exists { allow.tap() }
        }
        XCTAssertTrue(app.staticTexts["已保存到相册"].waitForExistence(timeout: 10))
        app.buttons["好"].tap()
        capture("markdown-image-preview")
        app.buttons["完成"].tap()
        app.buttons["刷新"].tap()
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "markdownImage").count, 1)
        XCTAssertTrue(app.staticTexts["图片后的说明。"].exists)
        XCTAssertEqual(server.capturedImageRequests.count, 2)
        for request in server.capturedImageRequests {
            XCTAssertTrue(request.contains("token=signed%2Bvalue%2Fpart&expires=123"))
            XCTAssertFalse(request.lowercased().contains("authorization:"))
            XCTAssertFalse(request.lowercased().contains("cookie:"))
        }
        capture("markdown-image-history")
    }

    func testDesktopIntelligentUIContextAndInteractions() throws {
        let server = try connectToFixture()
        server.enableChat(staged: true)
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap()
        input.typeText("测试桌面智能界面\n\n[客户端 Intelligent UI Beta 上下文]\n桌面版本能力\n[/客户端 Intelligent UI Beta 上下文]")
        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["停止生成"].waitForExistence(timeout: 10))
        let source = """
        ```INTELLIGENT-UI
        {"op":"begin",
         "version":2,"surfaceId":"mobile-test","title":"桌面兼容计划"}
        {"op":"state","key":"count","initial":2}
        {"op":"state","key":"tab","initial":"overview"}
        {"op":"node","node":{"id":"quantity","type":"stepper","label":"人数","bind":"count","min":1,"max":20}}
        {"op":"node","node":{"id":"total","type":"metric","label":"总价","value":{"op":"mul","args":[{"state":"count"},12]}}}
        {"op":"node","node":{"id":"tabs","type":"tabs","bind":"tab"}}
        {"op":"node","parent":"tabs","node":{"id":"overview","type":"section","label":"概览","value":"当前计划"}}
        {"op":"node","parent":"tabs","node":{"id":"details","type":"section","label":"详情","value":"桌面标签内容"}}
        {"op":"commit"}
        ```
        """
        server.appendReply(source)
        server.finishReply()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 10)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "桌面版本能力")).firstMatch.exists)
        if app.keyboards.firstMatch.exists {
            app.buttons["对话记录"].tap()
            app.buttons["收起侧栏"].tap()
        }
        let expand = app.buttons["展开智能界面"].firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 20))
        for _ in 0..<4 where !expand.isHittable { app.swipeDown() }
        expand.tap()
        XCTAssertTrue(app.navigationBars["智能界面"].waitForExistence(timeout: 5))
        let increase = expandedUI.buttons["增加人数"].firstMatch
        XCTAssertTrue(increase.waitForExistence(timeout: 15))
        increase.tap()
        XCTAssertTrue(expandedUI.staticTexts["36"].firstMatch.waitForExistence(timeout: 5))
        let details = expandedUI.descendants(matching: .any).matching(NSPredicate(format: "label == '详情'" )).firstMatch
        details.tap()
        XCTAssertTrue(expandedUI.staticTexts["桌面标签内容"].firstMatch.waitForExistence(timeout: 5))
        capture("intelligent-ui-desktop-tabs")
        app.buttons["完成"].tap()
        app.buttons["刷新"].tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 15))
        for _ in 0..<4 where !expand.isHittable { app.swipeDown() }
        expand.tap()
        XCTAssertTrue(expandedUI.staticTexts["36"].firstMatch.waitForExistence(timeout: 15))
        let next = expandedUI.buttons["用当前选择继续"].firstMatch
        for _ in 0..<3 where !next.isHittable { expandedUI.swipeUp() }
        XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        XCTAssertTrue(app.staticTexts["已带入智能界面和当前选择"].waitForExistence(timeout: 5))
        XCTAssertFalse((input.value as? String ?? "").contains("surfaceId"))
        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["停止生成"].waitForExistence(timeout: 10))
        let prompt = server.sentMessages.last ?? ""
        XCTAssertTrue(prompt.contains("[客户端当前界面选择]"))
        XCTAssertTrue(prompt.contains("\"revision\":1"))
        XCTAssertTrue(prompt.contains("\"count\":3"))
        server.appendReply("""
        ```intelligent-ui
        {"op":"begin","version":2,"surfaceId":"mobile-test","mode":"patch","baseRevision":1}
        {"op":"node","node":{"id":"total","type":"metric","label":"更新总价","value":99}}
        {"op":"commit"}
        ```
        """)
        server.finishReply()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 10)
        let expandedButtons = app.buttons.matching(identifier: "展开智能界面")
        let updated = expandedButtons.element(boundBy: max(0, expandedButtons.count - 1))
        for _ in 0..<4 where !updated.isHittable { app.swipeUp() }
        XCTAssertTrue(updated.waitForExistence(timeout: 10)); updated.tap()
        XCTAssertTrue(expandedUI.staticTexts["99"].firstMatch.waitForExistence(timeout: 15))
        capture("intelligent-ui-patch")
        app.buttons["完成"].tap()
    }

    func testIntelligentUIDiagramImageAndLocalApp() throws {
        let server = try connectToFixture()
        server.enableChat(staged: true)
        let input = app.descendants(matching: .any).matching(identifier: "消息").firstMatch
        input.tap(); input.typeText("交互图解和图片")
        app.buttons["发送"].tap()
        XCTAssertTrue(app.buttons["停止生成"].waitForExistence(timeout: 10))
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 240)).pngData { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 240))
        }.base64EncodedString()
        let code = "var n=7;function draw(){ui.render({version:1,title:'本地算法',state:{n:n},body:[{id:'status',type:'text',value:typeof fetch==='undefined'&&typeof XMLHttpRequest==='undefined'?'沙箱运行通过':'网络未隔离'},{id:'value',type:'metric',label:'本地结果',value:n},{id:'inc',type:'button',label:'计算加一',action:'event'}]})}ui.onEvent(function(){n++;draw()});draw();"
        let document: [String: Any] = ["version": 1, "title": "图解与算法", "state": ["part": "all"], "body": [
            ["id": "photo", "type": "image", "label": "兼容图片", "src": "data:image/png;base64," + bitmap],
            ["id": "drawing", "type": "diagram", "label": "结构图", "bind": "part", "width": 100, "height": 100,
             "parts": [["id": "partA", "label": "核心部件", "description": "已选择核心部件"]],
             "shapes": [["type": "circle", "x": 50, "y": 50, "r": 20, "part": "partA"]]],
            ["id": "algorithm", "type": "app", "label": "离线计算", "code": code]
        ]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self)
        server.appendReply("```intelligent-ui\n" + json + "\n```")
        server.finishReply()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["停止生成"])], timeout: 10)
        if app.keyboards.firstMatch.exists { app.buttons["对话记录"].tap(); app.buttons["收起侧栏"].tap() }
        let expand = app.buttons["展开智能界面"].firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 15))
        for _ in 0..<4 where !expand.isHittable { app.swipeDown() }
        expand.tap()
        let image = expandedUI.buttons["预览 兼容图片"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 15)); image.tap()
        XCTAssertTrue(app.navigationBars["兼容图片"].waitForExistence(timeout: 5))
        app.navigationBars["兼容图片"].buttons["完成"].tap()
        let part = expandedUI.switches.matching(identifier: "核心部件").element(boundBy: 1)
        for _ in 0..<4 where !part.isHittable { expandedUI.swipeUp() }
        part.tap()
        XCTAssertTrue(expandedUI.staticTexts["已选择核心部件"].firstMatch.waitForExistence(timeout: 5))
        let calculate = expandedUI.buttons["计算加一"].firstMatch
        for _ in 0..<5 where !calculate.isHittable { expandedUI.swipeUp() }
        XCTAssertTrue(expandedUI.staticTexts["沙箱运行通过"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(calculate.waitForExistence(timeout: 10)); calculate.tap()
        XCTAssertTrue(expandedUI.staticTexts["8"].firstMatch.waitForExistence(timeout: 5))
        capture("intelligent-ui-local-app")
        app.buttons["完成"].tap()
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
        if !app.buttons["连接我的 Being"].exists {
            app.tabBars.buttons["更多"].tap()
            XCTAssertTrue(app.navigationBars["更多"].waitForExistence(timeout: 10))
            app.buttons["beingConnection"].tap()
            let fixture = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'http://127.0.0.1:'")).firstMatch
            XCTAssertTrue(fixture.waitForExistence(timeout: 5), "仅清理隔离测试的 loopback 连接")
            app.buttons["断开连接"].tap()
            app.terminate()
            app.launch()
        }
        app.buttons["连接我的 Being"].tap()
        let link = app.secureTextFields["Being 完整连接地址"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText(server.endpoint + "?token=fixture")
        app.scrollViews.buttons["连接 Being"].tap()
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
