import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var authChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        if let registrar = self.registrar(forPlugin: "AliyunAuthChannel") {
            authChannel = FlutterMethodChannel(
                name: "com.aiaccounting/aliyun_auth",
                binaryMessenger: registrar.messenger()
            )

            authChannel?.setMethodCallHandler { [weak self] call, result in
                self?.handleMethodCall(call: call, result: result)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
}
