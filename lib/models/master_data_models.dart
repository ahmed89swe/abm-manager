import 'package:cloud_firestore/cloud_firestore.dart';

class Governorate {
  const Governorate({
    required this.id,
    this.managerId = '',
    required this.nameAr,
    required this.nameEn,
    this.isActive = true,
  });

  final String id;
  final String managerId;
  final String nameAr;
  final String nameEn;
  final bool isActive;

  String displayName(bool isAr) => isAr ? nameAr : (nameEn.isNotEmpty ? nameEn : nameAr);

  factory Governorate.fromMap(Map<String, dynamic> map, String id) {
    return Governorate(
      id: id,
      managerId: (map['managerId'] ?? '') as String,
      nameAr: (map['nameAr'] ?? '') as String,
      nameEn: (map['nameEn'] ?? '') as String,
      isActive: (map['isActive'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        if (managerId.isNotEmpty) 'managerId': managerId,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class DoctorEntity {
  const DoctorEntity({
    required this.id,
    required this.name,
    required this.specialty,
    required this.governorateId,
    required this.phone,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String specialty;
  final String governorateId;
  final String phone;
  final bool isActive;

  factory DoctorEntity.fromMap(Map<String, dynamic> map, String id) {
    return DoctorEntity(
      id: id,
      name: (map['name'] ?? '') as String,
      specialty: (map['specialty'] ?? '') as String,
      governorateId: (map['governorateId'] ?? '') as String,
      phone: (map['phone'] ?? '') as String,
      isActive: (map['isActive'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'specialty': specialty,
        'governorateId': governorateId,
        'phone': phone,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class PharmacyEntity {
  const PharmacyEntity({
    required this.id,
    required this.name,
    required this.governorateId,
    required this.address,
    this.phone = '',
    this.isActive = true,
  });

  final String id;
  final String name;
  final String governorateId;
  final String address;
  final String phone;
  final bool isActive;

  factory PharmacyEntity.fromMap(Map<String, dynamic> map, String id) {
    return PharmacyEntity(
      id: id,
      name: (map['name'] ?? '') as String,
      governorateId: (map['governorateId'] ?? '') as String,
      address: (map['address'] ?? '') as String,
      phone: (map['phone'] ?? '') as String,
      isActive: (map['isActive'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'governorateId': governorateId,
        'address': address,
        'phone': phone,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class WarehouseEntity {
  const WarehouseEntity({
    required this.id,
    required this.name,
    required this.governorateId,
    required this.address,
    this.phone = '',
    this.isActive = true,
  });

  final String id;
  final String name;
  final String governorateId;
  final String address;
  final String phone;
  final bool isActive;

  factory WarehouseEntity.fromMap(Map<String, dynamic> map, String id) {
    return WarehouseEntity(
      id: id,
      name: (map['name'] ?? '') as String,
      governorateId: (map['governorateId'] ?? '') as String,
      address: (map['address'] ?? '') as String,
      phone: (map['phone'] ?? '') as String,
      isActive: (map['isActive'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'governorateId': governorateId,
        'address': address,
        'phone': phone,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class MaterialEntity {
  const MaterialEntity({
    required this.id,
    this.managerId = '',
    required this.name,
    this.defaultUnitPrice,
    this.unit = 'علبة',
    this.isActive = true,
  });

  final String id;
  final String managerId;
  final String name;
  final double? defaultUnitPrice;
  final String unit;
  final bool isActive;

  factory MaterialEntity.fromMap(Map<String, dynamic> map, String id) {
    return MaterialEntity(
      id: id,
      managerId: (map['managerId'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      defaultUnitPrice: map['defaultUnitPrice'] != null
          ? (map['defaultUnitPrice'] as num).toDouble()
          : null,
      unit: (map['unit'] ?? 'علبة') as String,
      isActive: (map['isActive'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        if (managerId.isNotEmpty) 'managerId': managerId,
        'name': name,
        'defaultUnitPrice': defaultUnitPrice,
        'unit': unit,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
