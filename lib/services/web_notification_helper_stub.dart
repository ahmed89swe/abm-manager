bool isSupported() => false;

String getPermission() => 'unsupported';

Future<bool> init() async => false;

Future<String> requestPermission() async => 'unsupported';

Future<bool> showNotification({
  required String title,
  required String body,
  String tag = 'abm-notif',
}) async =>
    false;
