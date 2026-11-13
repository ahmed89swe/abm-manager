import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../models/audit_log_model.dart';
import '../services/audit_helper.dart';
import '../services/notification_service.dart';

class VersionRepository {
  VersionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _configDoc =>
      _firestore.collection('app_config').doc('version_info');

  Stream<AppVersionConfig?> watchVersionConfig() {
    return _configDoc.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return AppVersionConfig.fromMap(snap.data()!);
    });
  }

  Future<void> publishNewVersion({
    required AppUser manager,
    required AppVersionConfig config,
  }) async {
    await _configDoc.set(config.toMap(), SetOptions(merge: true));

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: manager,
      actionType: 'publish_version',
      descriptionAr:
          'نشر المدير الإصدار ${config.latestVersionName} - إجباري للمندوبين: ${config.isForceUpdate ? "نعم" : "لا"}',
      descriptionEn:
          'Manager published version ${config.latestVersionName} - Force (delegates): ${config.isForceUpdate}',
      metadata: {
        'versionName': config.latestVersionName,
        'isForceUpdate': config.isForceUpdate,
      },
    );

    final managerId = manager.effectiveManagerId;
    await NotificationService.instance.sendCloudNotification(
      managerId: managerId,
      titleAr: 'يتوفر تحديث جديد للتطبيق (${config.latestVersionName})',
      titleEn: 'New App Update Available (${config.latestVersionName})',
      bodyAr: config.releaseNotesAr.isNotEmpty
          ? config.releaseNotesAr
          : 'يرجى تحديث التطبيق للحصول على أحدث التحسينات.',
      bodyEn: config.releaseNotesEn.isNotEmpty
          ? config.releaseNotesEn
          : 'Please update the app to get the latest improvements.',
      type: 'app_update',
      targetRole: 'delegate',
      audienceTags: [
        'MANAGER_$managerId',
        'DELEGATES_$managerId',
        'ALL_$managerId',
      ],
      createdByUid: manager.uid,
    );
  }
}
