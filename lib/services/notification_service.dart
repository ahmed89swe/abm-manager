import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/app_user.dart';
import '../models/audit_log_model.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background FCM message: ${message.messageId}');
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _channelId = 'abm_high_importance_channel';
  static const String _channelName = 'ABM Manager Notifications';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _cloudListener;
  StreamSubscription<String>? _registrationSub;
  final StreamController<AppNotificationModel> _inAppController =
      StreamController<AppNotificationModel>.broadcast();

  /// بث إشعارات فورية للعرض داخل التطبيق والويب
  Stream<AppNotificationModel> get liveNotificationsStream =>
      _inAppController.stream;

  final Set<String> _shownNotificationIds = <String>{};
  DateTime _listenerStartedAt = DateTime.now();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(settings: initSettings);

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'إشعارات العمليات المالية والفواتير والتحديثات',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notif = message.notification;
        if (notif != null) {
          showLocalNotification(
            id: message.hashCode,
            title: notif.title ?? 'ABM Manager',
            body: notif.body ?? '',
          );
        }
      });
    } catch (e) {
      debugPrint('FCM setup warning: $e');
    }
  }

  /// ربط توكن FCM ومراقبة سحابة الإشعارات الفورية لهذا المستخدم وفق audienceTags
  Future<void> attachUserListener(AppUser user, {required bool isAr}) async {
    await initialize();
    if (!kIsWeb) {
      await _registerFcmToken(user);
    }

    await _cloudListener?.cancel();
    _listenerStartedAt = DateTime.now().subtract(const Duration(seconds: 2));

    Query<Map<String, dynamic>> query;
    if (user.isManager) {
      query = _firestore
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(30);
    } else {
      final tags = <String>[
        'USER_${user.uid}',
        if (user.governorateId != null && user.governorateId!.isNotEmpty)
          'GOV_${user.governorateId}',
        'ALL',
      ];
      query = _firestore
          .collection('notifications')
          .where('audienceTags', arrayContainsAny: tags);
    }

    _cloudListener = query.snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;
        final notif = AppNotificationModel.fromMap(data, doc.id);

        if (_shownNotificationIds.contains(notif.id)) continue;
        if (notif.createdByUid == user.uid) continue;
        final createdAt = notif.createdAt;
        if (createdAt != null && createdAt.isBefore(_listenerStartedAt)) {
          _shownNotificationIds.add(notif.id);
          continue;
        }

        _shownNotificationIds.add(notif.id);
        _inAppController.add(notif);
        if (!kIsWeb) {
          showLocalNotification(
            id: notif.id.hashCode,
            title: isAr ? notif.titleAr : notif.titleEn,
            body: isAr ? notif.bodyAr : notif.bodyEn,
          );
        }
      }
    }, onError: (e) {
      debugPrint('Notification listener error: $e');
    });
  }

  Future<void> detachListener() async {
    await _cloudListener?.cancel();
    _cloudListener = null;
    await _registrationSub?.cancel();
    _registrationSub = null;
  }

  Future<void> _registerFcmToken(AppUser user) async {
    if (kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await _registrationSub?.cancel();
      _registrationSub = messaging.onRegistered.listen((token) async {
        if (!user.fcmTokens.contains(token)) {
          await _firestore.collection('users').doc(user.uid).update({
            'fcmTokens': FieldValue.arrayUnion([token]),
          });
        }
      });
      await messaging.register();
      if (user.isManager) {
        await messaging.subscribeToTopic('managers');
      } else {
        await messaging.subscribeToTopic('delegates');
      }
      await messaging.subscribeToTopic('all_users');
    } catch (e) {
      debugPrint('FCM token registration skipped: $e');
    }
  }

  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  /// إرسال إشعار سحابي محدد المستلمين عبر audienceTags
  Future<void> sendCloudNotification({
    required String titleAr,
    required String titleEn,
    required String bodyAr,
    required String bodyEn,
    required String type,
    required String targetRole, // manager | delegate | all
    required List<String> audienceTags,
    List<String> targetUserIds = const [],
    String? referenceId,
    required String createdByUid,
  }) async {
    await _firestore.collection('notifications').add({
      'titleAr': titleAr,
      'titleEn': titleEn,
      'bodyAr': bodyAr,
      'bodyEn': bodyEn,
      'type': type,
      'targetRole': targetRole,
      'targetUserIds': targetUserIds,
      'audienceTags': audienceTags,
      'readByUids': <String>[createdByUid],
      'referenceId': referenceId,
      'createdByUid': createdByUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAsRead(String notificationId, String uid) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'readByUids': FieldValue.arrayUnion([uid]),
    });
  }
}
