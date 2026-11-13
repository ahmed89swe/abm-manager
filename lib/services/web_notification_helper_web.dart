import 'dart:js_interop';

@JS('abmNotify')
external JSObject? get _abmNotify;

@JS('abmNotify.isSupported')
external bool _jsIsSupported();

@JS('abmNotify.getPermission')
external String _jsGetPermission();

@JS('abmNotify.init')
external JSPromise<JSBoolean> _jsInit();

@JS('abmNotify.requestPermission')
external JSPromise<JSString> _jsRequestPermission();

@JS('abmNotify.show')
external JSPromise<JSBoolean> _jsShow(String title, String body, String tag);

bool isSupported() {
  if (_abmNotify == null) return false;
  try {
    return _jsIsSupported();
  } catch (_) {
    return false;
  }
}

String getPermission() {
  if (_abmNotify == null) return 'unsupported';
  try {
    return _jsGetPermission();
  } catch (_) {
    return 'unsupported';
  }
}

Future<bool> init() async {
  if (_abmNotify == null) return false;
  try {
    final result = await _jsInit().toDart;
    return result.toDart;
  } catch (_) {
    return false;
  }
}

Future<String> requestPermission() async {
  if (_abmNotify == null) return 'unsupported';
  try {
    final result = await _jsRequestPermission().toDart;
    return result.toDart;
  } catch (_) {
    return getPermission();
  }
}

Future<bool> showNotification({
  required String title,
  required String body,
  String tag = 'abm-notif',
}) async {
  if (_abmNotify == null) return false;
  try {
    final result = await _jsShow(title, body, tag).toDart;
    return result.toDart;
  } catch (_) {
    return false;
  }
}
