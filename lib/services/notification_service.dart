import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class NotificationService {
  static const String _appId = '63a2ae14-b781-4656-8725-fcf293178e8a';

  /// Initializes the OneSignal SDK and sets up all listeners.
  /// Call this once from main() before runApp().
  static Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('[OneSignal] SDK is not supported on Web. Skipping initialization.');
      return;
    }

    // Enable verbose logs in debug mode for easier troubleshooting
    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    }

    // 1. Initialize the SDK with the OneSignal App ID
    OneSignal.initialize(_appId);

    // 2. Request permission to show notifications (iOS + Android 13+)
    await OneSignal.Notifications.requestPermission(true);

    // 3. Handle notifications clicked when app is in background/killed
    OneSignal.Notifications.addClickListener(_onNotificationClicked);

    // 4. Handle notifications received while app is in foreground
    OneSignal.Notifications.addForegroundWillDisplayListener(
      _onForegroundNotification,
    );

    debugPrint('[OneSignal] Initialized successfully.');
  }

  /// Associates the logged-in user's email with OneSignal so the backend
  /// can target them specifically.
  static void loginUser(String externalUserId) {
    if (kIsWeb) return;
    OneSignal.login(externalUserId);
    debugPrint('[OneSignal] Logged in user: $externalUserId');
  }

  /// Clears the user association on logout.
  static void logoutUser() {
    if (kIsWeb) return;
    OneSignal.logout();
    debugPrint('[OneSignal] User logged out from OneSignal.');
  }

  /// Returns the OneSignal subscription ID for the current device.
  /// This ID must be sent to your backend to send targeted notifications.
  static String? getSubscriptionId() {
    if (kIsWeb) return null;
    return OneSignal.User.pushSubscription.id;
  }

  // ---------------------------------------------------------------------------
  // Private Listeners
  // ---------------------------------------------------------------------------

  static void _onNotificationClicked(OSNotificationClickEvent event) {
    final notification = event.notification;
    debugPrint('[OneSignal] Notification clicked: ${notification.title}');

    // Read any custom data payload sent from the backend
    final Map<String, dynamic>? data = notification.additionalData;
    if (data != null) {
      debugPrint('[OneSignal] Additional data: $data');
      // TODO: Use navigatorKey to navigate based on data (e.g., open specific email)
      // Example:
      // final String? emailId = data['email_uid'] as String?;
      // if (emailId != null) {
      //   navigatorKey.currentState?.pushNamed('/email', arguments: emailId);
      // }
    }
  }

  static void _onForegroundNotification(
    OSNotificationWillDisplayEvent event,
  ) {
    debugPrint(
      '[OneSignal] Foreground notification: ${event.notification.title}',
    );
    // Display the notification banner even when the app is open
    event.notification.display();
  }
}
