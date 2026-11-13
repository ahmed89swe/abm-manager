import 'web_notification_helper_stub.dart'
    if (dart.library.js_interop) 'web_notification_helper_web.dart' as impl;

class WebNotificationHelper {
  const WebNotificationHelper._();

  static bool get isSupported => impl.isSupported();

  /// Returns 'granted', 'denied', 'default', or 'unsupported'.
  static String get permission => impl.getPermission();

  static Future<bool> init() => impl.init();

  static Future<String> requestPermission() => impl.requestPermission();

  static Future<bool> showNotification({
    required String title,
    required String body,
    String tag = 'abm-notif',
  }) =>
      impl.showNotification(title: title, body: body, tag: tag);
}
