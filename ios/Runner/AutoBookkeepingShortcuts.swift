import AppIntents
import Foundation

@available(iOS 16.0, *)
struct RecordBookkeepingTextIntent: AppIntent {
    static var title: LocalizedStringResource = "AI Auto Bookkeeping"
    static var description = IntentDescription(
        "Send extracted bill text to AI Wealth Tracker for automatic bookkeeping."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Bill Text")
    var billText: String

    init() {
        billText = ""
    }

    init(billText: String) {
        self.billText = billText
    }

    func perform() async throws -> some IntentResult {
        AutoBookkeepingShortcutStore.savePendingText(billText)
        return .result()
    }
}

@available(iOS 16.0, *)
struct AIWealthTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordBookkeepingTextIntent(),
            phrases: [
                "Use \(.applicationName) to auto bookkeep",
                "Record expense with \(.applicationName)",
                "用 \(.applicationName) 自动记账",
                "让 \(.applicationName) 记账"
            ],
            shortTitle: "Auto Bookkeeping",
            systemImageName: "wand.and.stars"
        )
    }
}
