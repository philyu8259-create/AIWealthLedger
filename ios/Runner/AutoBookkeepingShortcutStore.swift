import Foundation

enum AutoBookkeepingShortcutStore {
    static let notificationName = Notification.Name("AutoBookkeepingShortcutTextSaved")

    private static let pendingTextKey = "auto_bookkeeping_pending_text_v1"

    static func savePendingText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        UserDefaults.standard.set(trimmed, forKey: pendingTextKey)
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: ["text": trimmed]
        )
    }

    static func consumePendingText() -> String? {
        guard let text = UserDefaults.standard.string(forKey: pendingTextKey) else {
            return nil
        }

        UserDefaults.standard.removeObject(forKey: pendingTextKey)
        UserDefaults.standard.synchronize()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
