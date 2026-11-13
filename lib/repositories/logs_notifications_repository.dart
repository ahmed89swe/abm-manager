import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../models/audit_log_model.dart';

class LogsNotificationsRepository {
  LogsNotificationsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<AuditLogModel>> watchAuditLogs(AppUser user) {
    final managerId = user.effectiveManagerId;
    if (managerId.isEmpty) return Stream.value(const []);
    Query<Map<String, dynamic>> query = _firestore
        .collection('audit_logs')
        .where('managerId', isEqualTo: managerId);
    if (user.isDelegate) {
      query = query.where('actorUid', isEqualTo: user.uid);
    }
    return query.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => AuditLogModel.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) {
        final ta = a.timestamp ?? DateTime(2000);
        final tb = b.timestamp ?? DateTime(2000);
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  Stream<List<AppNotificationModel>> watchNotifications(AppUser user) {
    final managerId = user.effectiveManagerId;
    if (managerId.isEmpty) return Stream.value(const []);
    if (user.isManager) {
      return _firestore
          .collection('notifications')
          .where('managerId', isEqualTo: managerId)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => AppNotificationModel.fromMap(d.data(), d.id))
              .toList());
    }

    final tags = <String>[
      'USER_${user.uid}',
      if (user.governorateId != null && user.governorateId!.isNotEmpty)
        'GOV_${user.governorateId}',
      'DELEGATES_$managerId',
      'ALL_$managerId',
    ];

    return _firestore
        .collection('notifications')
        .where('managerId', isEqualTo: managerId)
        .where('audienceTags', arrayContainsAny: tags)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AppNotificationModel.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) {
        final ta = a.createdAt ?? DateTime(2000);
        final tb = b.createdAt ?? DateTime(2000);
        return tb.compareTo(ta);
      });
      return list;
    });
  }
}
