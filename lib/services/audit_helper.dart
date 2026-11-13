import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';

class AuditHelper {
  AuditHelper._();

  static Future<void> recordLog({
    required FirebaseFirestore firestore,
    required AppUser actor,
    required String actionType,
    required String descriptionAr,
    required String descriptionEn,
    Map<String, dynamic> metadata = const {},
  }) async {
    await firestore.collection('audit_logs').add({
      'actorUid': actor.uid,
      'actorName': actor.name,
      'actorRole': actor.role.value,
      'actionType': actionType,
      'descriptionAr': descriptionAr,
      'descriptionEn': descriptionEn,
      'metadata': metadata,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
