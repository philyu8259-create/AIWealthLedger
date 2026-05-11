import XCTest

final class RunnerAutoBookkeepingUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["--ui-testing-auto-bookkeeping"]
        app.launch()
    }

    func testAutoBookkeepingSettingsPageOpensOnDevice() throws {
        let setupPage = app.descendants(matching: .any)["auto-bookkeeping-page"]
        XCTAssertTrue(
            setupPage.waitForExistence(timeout: 20),
            "Auto bookkeeping setup page did not appear.\n\(app.debugDescription)"
        )

        XCTAssertTrue(
            waitForAnyTextContaining(["Turn a payment screen into an entry", "把付款页面变成一笔账单"], timeout: 8),
            "Auto bookkeeping hero copy is missing.\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["auto-bookkeeping-open-shortcuts-button"]
                .waitForExistence(timeout: 4),
            "Open Shortcuts button is missing.\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            waitForAnyTextContaining(["Shortcut flow", "快捷指令流程"], timeout: 4),
            "Shortcut flow instructions are missing.\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            waitForAnyTextContaining(["Bill Text", "提取的文本"], timeout: 4, scrolls: 3),
            "Bill Text variable binding instructions are missing.\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            waitForAnyTextContaining(["Settings > Accessibility > Touch > Back Tap", "设置 > 辅助功能 > 触控 > 轻点背面"], timeout: 4, scrolls: 3),
            "Back Tap setup path is missing.\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            waitForAnyTextContaining(["Privacy boundary", "隐私边界"], timeout: 4, scrolls: 3),
            "Privacy boundary copy is missing.\n\(app.debugDescription)"
        )

        let testButton = app.descendants(matching: .any)["auto-bookkeeping-test-button"]
        XCTAssertTrue(
            testButton.waitForExistence(timeout: 4),
            "Auto bookkeeping test button is missing.\n\(app.debugDescription)"
        )
    }

    private func waitForAnyTextContaining(
        _ snippets: [String],
        timeout: TimeInterval,
        scrolls: Int = 0
    ) -> Bool {
        for attempt in 0...scrolls {
            if waitWithoutScrollingForAnyTextContaining(snippets, timeout: timeout) {
                return true
            }
            if attempt < scrolls {
                app.swipeUp()
            }
        }
        return false
    }

    private func waitWithoutScrollingForAnyTextContaining(
        _ snippets: [String],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if hasStaticText(containingAny: snippets) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        return hasStaticText(containingAny: snippets)
    }

    private func hasStaticText(containingAny snippets: [String]) -> Bool {
        let texts = app.staticTexts.allElementsBoundByIndex
        return texts.contains { element in
            guard element.exists else { return false }
            return snippets.contains { element.label.contains($0) }
        }
    }
}
