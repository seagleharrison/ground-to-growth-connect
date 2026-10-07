import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var pendingRegistration: FlutterResult?

  // A notification the person tapped. If the app wasn't running yet, Dart asks
  // for it once it's ready.
  private var launchTap: [String: String]?
  private var dartIsListening = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "g2g/push",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    pushChannel = channel
  }

  // MARK: - Calls from Dart

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async { result(Self.statusName(settings.authorizationStatus)) }
      }

    case "register":
      let ask = (call.arguments as? [String: Any])?["ask"] as? Bool ?? false
      register(ask: ask, result: result)

    case "setBadge":
      let count = (call.arguments as? [String: Any])?["count"] as? Int ?? 0
      DispatchQueue.main.async {
        if #available(iOS 16.0, *) {
          UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        } else {
          UIApplication.shared.applicationIconBadgeNumber = count
        }
        result(nil)
      }

    case "takeLaunchTap":
      dartIsListening = true
      let tap = launchTap
      launchTap = nil
      result(tap)

    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func statusName(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    default: return "authorized"
    }
  }

  /// Asks permission only when told to (`ask`), so the system prompt appears at
  /// a moment the person chose rather than the instant the app opens.
  private func register(ask: Bool, result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        switch settings.authorizationStatus {
        case .notDetermined:
          guard ask else {
            result(["status": "notDetermined"])
            return
          }
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
              if granted {
                self.beginRegistration(result: result)
              } else {
                result(["status": "denied"])
              }
            }
          }
        case .denied:
          result(["status": "denied"])
        default:
          self.beginRegistration(result: result)
        }
      }
    }
  }

  private func beginRegistration(result: @escaping FlutterResult) {
    // Only one answer is ever pending; a newer request replaces an older one.
    pendingRegistration?(["status": "failed", "error": "superseded"])
    pendingRegistration = result
    UIApplication.shared.registerForRemoteNotifications()
  }

  // MARK: - Apple's callbacks

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    pendingRegistration?(["status": "authorized", "token": token])
    pendingRegistration = nil
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    pendingRegistration?(["status": "failed", "error": error.localizedDescription])
    pendingRegistration = nil
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // MARK: - Notifications arriving

  /// While the app is open, still show the banner: a message can arrive while
  /// someone is on another screen.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound, .badge])
  }

  /// The person tapped a notification: tell Dart so it can open the right
  /// screen (or keep it until Dart is ready, on a cold start).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    var data: [String: String] = [:]
    if let raw = userInfo["data"] as? [String: Any] {
      for (key, value) in raw { data[key] = "\(value)" }
    }
    if dartIsListening, let channel = pushChannel {
      channel.invokeMethod("onTap", arguments: data)
    } else {
      launchTap = data
    }
    completionHandler()
  }
}
