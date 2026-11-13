import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../models/master_data_models.dart';
import '../services/audit_helper.dart';
import '../services/notification_service.dart';

class MasterDataRepository {
  MasterDataRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<Governorate>> watchGovernorates(String managerId) {
    if (managerId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('governorates')
        .where('managerId', isEqualTo: managerId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => Governorate.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => a.nameAr.compareTo(b.nameAr));
      return list;
    });
  }

  Stream<List<MaterialEntity>> watchMaterials(String managerId) {
    if (managerId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('materials')
        .where('managerId', isEqualTo: managerId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => MaterialEntity.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<void> saveDocument({
    required AppUser actor,
    required String collection,
    String? docId,
    required Map<String, dynamic> data,
    required String entityLabelAr,
    required String entityLabelEn,
  }) async {
    final managerId = actor.effectiveManagerId;
    final payload = {
      ...data,
      'managerId': managerId,
    };
    final col = _firestore.collection(collection);
    final isNew = docId == null;
    if (isNew) {
      await col.add(payload);
    } else {
      await col.doc(docId).update(payload);
    }

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: actor,
      actionType: isNew ? 'master_add_$collection' : 'master_edit_$collection',
      descriptionAr: isNew
          ? 'أضاف المدير $entityLabelAr'
          : 'عدّل المدير $entityLabelAr',
      descriptionEn: isNew
          ? 'Manager added $entityLabelEn'
          : 'Manager updated $entityLabelEn',
    );

    await NotificationService.instance.sendCloudNotification(
      managerId: managerId,
      titleAr: 'تحديث البيانات الأساسية',
      titleEn: 'Master Data Updated',
      bodyAr: isNew
          ? 'تمت إضافة $entityLabelAr'
          : 'تم تعديل $entityLabelAr',
      bodyEn: isNew
          ? 'Added $entityLabelEn'
          : 'Updated $entityLabelEn',
      type: 'master_data',
      targetRole: 'all',
      audienceTags: ['MANAGER_$managerId', 'ALL_$managerId'],
      createdByUid: actor.uid,
    );
  }

  Future<void> deleteDocument({
    required AppUser actor,
    required String collection,
    required String docId,
    required String entityLabelAr,
    required String entityLabelEn,
  }) async {
    await _firestore.collection(collection).doc(docId).delete();
    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: actor,
      actionType: 'master_delete_$collection',
      descriptionAr: 'حذف المدير $entityLabelAr',
      descriptionEn: 'Manager deleted $entityLabelEn',
    );
  }
}
