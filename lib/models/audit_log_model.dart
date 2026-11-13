import 'package:cloud_firestore/cloud_firestore.dart';

class AuditLogModel {
  const AuditLogModel({
    required this.id,
    this.managerId = '',
    required this.actorUid,
    required this.actorName,
    required this.actorRole,
    required this.actionType,
    required this.descriptionAr,
    required this.descriptionEn,
    this.metadata = const {},
    this.timestamp,
  });

  final String id;
  final String managerId;
  final String actorUid;
  final String actorName;
  final String actorRole;
  final String actionType;
  final String descriptionAr;
  final String descriptionEn;
  final Map<String, dynamic> metadata;
  final DateTime? timestamp;

  factory AuditLogModel.fromMap(Map<String, dynamic> map, String id) {
    return AuditLogModel(
      id: id,
      managerId: (map['managerId'] ?? '') as String,
      actorUid: (map['actorUid'] ?? '') as String,
      actorName: (map['actorName'] ?? '') as String,
      actorRole: (map['actorRole'] ?? '') as String,
      actionType: (map['actionType'] ?? '') as String,
      descriptionAr: (map['descriptionAr'] ?? '') as String,
      descriptionEn: (map['descriptionEn'] ?? '') as String,
      metadata: Map<String, dynamic>.from(map['metadata'] ?? const {}),
      timestamp: (map['timestamp'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (managerId.isNotEmpty) 'managerId': managerId,
      'actorUid': actorUid,
      'actorName': actorName,
      'actorRole': actorRole,
      'actionType': actionType,
      'descriptionAr': descriptionAr,
      'descriptionEn': descriptionEn,
      'metadata': metadata,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}

class AppNotificationModel {
  const AppNotificationModel({
    required this.id,
    this.managerId = '',
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyEn,
    required this.type,
    required this.targetRole,
    this.targetUserIds = const [],
    this.audienceTags = const [],
    this.readByUids = const [],
    this.referenceId,
    this.createdByUid,
    this.createdAt,
  });

  final String id;
  final String managerId;
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final String type;
  final String targetRole; // manager | delegate | all
  final List<String> targetUserIds;
  final List<String> audienceTags; // ['MANAGER_{mId}', 'USER_xxx', 'GOV_yyy', 'ALL_{mId}']
  final List<String> readByUids;
  final String? referenceId;
  final String? createdByUid;
  final DateTime? createdAt;

  bool isReadBy(String uid) => readByUids.contains(uid);

  factory AppNotificationModel.fromMap(Map<String, dynamic> map, String id) {
    return AppNotificationModel(
      id: id,
      managerId: (map['managerId'] ?? '') as String,
      titleAr: (map['titleAr'] ?? '') as String,
      titleEn: (map['titleEn'] ?? '') as String,
      bodyAr: (map['bodyAr'] ?? '') as String,
      bodyEn: (map['bodyEn'] ?? '') as String,
      type: (map['type'] ?? 'general') as String,
      targetRole: (map['targetRole'] ?? 'all') as String,
      targetUserIds: List<String>.from(map['targetUserIds'] ?? const []),
      audienceTags: List<String>.from(map['audienceTags'] ?? const []),
      readByUids: List<String>.from(map['readByUids'] ?? const []),
      referenceId: map['referenceId'] as String?,
      createdByUid: map['createdByUid'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (managerId.isNotEmpty) 'managerId': managerId,
      'titleAr': titleAr,
      'titleEn': titleEn,
      'bodyAr': bodyAr,
      'bodyEn': bodyEn,
      'type': type,
      'targetRole': targetRole,
      'targetUserIds': targetUserIds,
      'audienceTags': audienceTags,
      'readByUids': readByUids,
      'referenceId': referenceId,
      'createdByUid': createdByUid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class AppVersionConfig {
  const AppVersionConfig({
    required this.latestVersionName,
    this.latestBuildNumber = 1,
    this.minRequiredBuildNumber = 1,
    required this.isForceUpdate,
    required this.downloadUrl,
    required this.releaseNotesAr,
    required this.releaseNotesEn,
    this.updatedAt,
  });

  final String latestVersionName;
  final int latestBuildNumber;
  final int minRequiredBuildNumber;
  final bool isForceUpdate;
  final String downloadUrl;
  final String releaseNotesAr;
  final String releaseNotesEn;
  final DateTime? updatedAt;

  factory AppVersionConfig.fromMap(Map<String, dynamic> map) {
    return AppVersionConfig(
      latestVersionName: (map['latestVersionName'] ?? '1.0.0') as String,
      latestBuildNumber: ((map['latestBuildNumber'] ?? 1) as num).toInt(),
      minRequiredBuildNumber:
          ((map['minRequiredBuildNumber'] ?? 1) as num).toInt(),
      isForceUpdate: (map['isForceUpdate'] ?? false) as bool,
      downloadUrl: (map['downloadUrl'] ?? '') as String,
      releaseNotesAr: (map['releaseNotesAr'] ?? '') as String,
      releaseNotesEn: (map['releaseNotesEn'] ?? '') as String,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latestVersionName': latestVersionName,
      'latestBuildNumber': latestBuildNumber,
      'minRequiredBuildNumber': minRequiredBuildNumber,
      'isForceUpdate': isForceUpdate,
      'downloadUrl': downloadUrl,
      'releaseNotesAr': releaseNotesAr,
      'releaseNotesEn': releaseNotesEn,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
