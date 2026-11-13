import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole {
  manager,
  delegate;

  static UserRole fromString(String? value) {
    return value == 'manager' ? UserRole.manager : UserRole.delegate;
  }

  String get value => name;
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.managerId,
    this.governorateId,
    this.governorateName,
    this.virtualBoxBalance = 0,
    this.isActive = true,
    this.fcmTokens = const [],
    this.photoUrl,
    this.avatarBase64,
    this.createdAt,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final String? managerId;
  final String? governorateId;
  final String? governorateName;
  final double virtualBoxBalance;
  final bool isActive;
  final List<String> fcmTokens;
  final String? photoUrl;
  final String? avatarBase64;
  final DateTime? createdAt;

  bool get isManager => role == UserRole.manager;
  bool get isDelegate => role == UserRole.delegate;

  /// المعرّف العازل لبيانات هذا المدير وفريقه بالكامل
  String get effectiveManagerId =>
      (managerId != null && managerId!.isNotEmpty)
          ? managerId!
          : (isManager ? uid : '');

  Uint8List? get avatarBytes {
    if (avatarBase64 == null || avatarBase64!.isEmpty) return null;
    try {
      return base64Decode(avatarBase64!);
    } catch (_) {
      return null;
    }
  }

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) {
    final role = UserRole.fromString(map['role'] as String?);
    final rawManagerId = (map['managerId'] as String?)?.trim();
    return AppUser(
      uid: uid,
      name: (map['name'] ?? '') as String,
      email: (map['email'] ?? '') as String,
      phone: (map['phone'] ?? '') as String,
      role: role,
      managerId: (rawManagerId != null && rawManagerId.isNotEmpty)
          ? rawManagerId
          : (role == UserRole.manager ? uid : null),
      governorateId: map['governorateId'] as String?,
      governorateName: map['governorateName'] as String?,
      virtualBoxBalance: ((map['virtualBoxBalance'] ?? 0) as num).toDouble(),
      isActive: (map['isActive'] ?? true) as bool,
      fcmTokens: List<String>.from(map['fcmTokens'] ?? const []),
      photoUrl: map['photoUrl'] as String?,
      avatarBase64: map['avatarBase64'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.value,
      'managerId': (managerId != null && managerId!.isNotEmpty)
          ? managerId
          : (isManager ? uid : null),
      'governorateId': governorateId,
      'governorateName': governorateName,
      'virtualBoxBalance': virtualBoxBalance,
      'isActive': isActive,
      'fcmTokens': fcmTokens,
      'photoUrl': photoUrl,
      'avatarBase64': avatarBase64,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  AppUser copyWith({
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    String? managerId,
    String? governorateId,
    String? governorateName,
    double? virtualBoxBalance,
    bool? isActive,
    List<String>? fcmTokens,
    String? photoUrl,
    String? avatarBase64,
  }) {
    return AppUser(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      managerId: managerId ?? this.managerId,
      governorateId: governorateId ?? this.governorateId,
      governorateName: governorateName ?? this.governorateName,
      virtualBoxBalance: virtualBoxBalance ?? this.virtualBoxBalance,
      isActive: isActive ?? this.isActive,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      photoUrl: photoUrl ?? this.photoUrl,
      avatarBase64: avatarBase64 ?? this.avatarBase64,
      createdAt: createdAt,
    );
  }
}
