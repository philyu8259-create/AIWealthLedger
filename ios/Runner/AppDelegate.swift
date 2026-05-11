import Flutter
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, SKRequestDelegate {
    private var authChannel: FlutterMethodChannel?
    private var receiptChannel: FlutterMethodChannel?
    private var autoBookkeepingChannel: FlutterMethodChannel?
    private var receiptRefreshRequest: SKReceiptRefreshRequest?
    private var pendingReceiptResult: FlutterResult?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        configureUITestLaunchState()
        GeneratedPluginRegistrant.register(with: self)

        if let registrar = self.registrar(forPlugin: "AliyunAuthChannel") {
            authChannel = FlutterMethodChannel(
                name: "com.aiaccounting/aliyun_auth",
                binaryMessenger: registrar.messenger()
            )

            receiptChannel = FlutterMethodChannel(
                name: "com.aiaccounting/app_store_receipt",
                binaryMessenger: registrar.messenger()
            )

            autoBookkeepingChannel = FlutterMethodChannel(
                name: "com.aiaccounting/auto_bookkeeping",
                binaryMessenger: registrar.messenger()
            )

            authChannel?.setMethodCallHandler { [weak self] call, result in
                self?.handleMethodCall(call: call, result: result)
            }

            receiptChannel?.setMethodCallHandler { [weak self] call, result in
                self?.handleReceiptMethodCall(call: call, result: result)
            }

            autoBookkeepingChannel?.setMethodCallHandler { [weak self] call, result in
                self?.handleAutoBookkeepingMethodCall(call: call, result: result)
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAutoBookkeepingTextSaved(_:)),
                name: AutoBookkeepingShortcutStore.notificationName,
                object: nil
            )
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func configureUITestLaunchState() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing-auto-bookkeeping") else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "flutter.has_logged_in")
        defaults.set("/auto_bookkeeping", forKey: "flutter.ui_test_initial_route")
        defaults.synchronize()
    }

    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            result(true)
        case "startLogin", "closeLoginPage":
            // ATAuth SDK removed; use SMS login instead
            result(FlutterError(code: "NOT_SUPPORTED", message: "One-click login unavailable", details: nil))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleReceiptMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getReceiptData":
            if let receiptData = loadLocalReceiptData() {
                result(receiptData)
                return
            }

            if pendingReceiptResult != nil {
                result(FlutterError(code: "RECEIPT_REFRESH_IN_PROGRESS", message: "Receipt refresh already in progress", details: nil))
                return
            }

            pendingReceiptResult = result
            let request = SKReceiptRefreshRequest()
            receiptRefreshRequest = request
            request.delegate = self
            request.start()
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleAutoBookkeepingMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "consumePendingText":
            result(AutoBookkeepingShortcutStore.consumePendingText())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @objc private func handleAutoBookkeepingTextSaved(_ notification: Notification) {
        guard let text = AutoBookkeepingShortcutStore.consumePendingText()
            ?? notification.userInfo?["text"] as? String else {
            return
        }

        autoBookkeepingChannel?.invokeMethod("recordText", arguments: text)
    }

    private func loadLocalReceiptData() -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return nil
        }

        guard let data = try? Data(contentsOf: receiptURL), !data.isEmpty else {
            return nil
        }

        return data.base64EncodedString()
    }

    func requestDidFinish(_ request: SKRequest) {
        defer {
            receiptRefreshRequest = nil
            pendingReceiptResult = nil
        }

        guard let result = pendingReceiptResult else {
            return
        }

        if let receiptData = loadLocalReceiptData() {
            result(receiptData)
        } else {
            result(
                FlutterError(
                    code: "NO_RECEIPT",
                    message: "App Store receipt not found after refresh",
                    details: nil
                )
            )
        }
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        defer {
            receiptRefreshRequest = nil
            pendingReceiptResult = nil
        }

        pendingReceiptResult?(
            FlutterError(
                code: "RECEIPT_REFRESH_FAILED",
                message: error.localizedDescription,
                details: nil
            )
        )
    }
}
