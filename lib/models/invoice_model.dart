import 'package:cloud_firestore/cloud_firestore.dart';

enum InvoiceAssignmentType {
  specificDelegate,
  manager,
  allGovernorateDelegates;

  static InvoiceAssignmentType fromString(String? val) {
    switch (val) {
      case 'specific_delegate':
        return InvoiceAssignmentType.specificDelegate;
      case 'manager':
        return InvoiceAssignmentType.manager;
      case 'all_governorate_delegates':
      default:
        return InvoiceAssignmentType.allGovernorateDelegates;
    }
  }

  String get firestoreValue {
    switch (this) {
      case InvoiceAssignmentType.specificDelegate:
        return 'specific_delegate';
      case InvoiceAssignmentType.manager:
        return 'manager';
      case InvoiceAssignmentType.allGovernorateDelegates:
        return 'all_governorate_delegates';
    }
  }
}

enum InvoiceStatus {
  unpaid,
  paid;

  static InvoiceStatus fromString(String? val) =>
      val == 'paid' ? InvoiceStatus.paid : InvoiceStatus.unpaid;
}

class InvoiceItem {
  const InvoiceItem({
    required this.materialId,
    required this.materialName,
    required this.quantity,
    this.unitPrice,
  });

  final String materialId;
  final String materialName;
  final int quantity;
  final double? unitPrice; // اختياري عند الإنشاء، يمكن إدخاله عند التسديد

  double get totalPrice => (unitPrice ?? 0) * quantity;

  bool get hasPrice => unitPrice != null && unitPrice! > 0;

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      materialId: (map['materialId'] ?? '') as String,
      materialName: (map['materialName'] ?? '') as String,
      quantity: ((map['quantity'] ?? 1) as num).toInt(),
      unitPrice:
          map['unitPrice'] != null ? (map['unitPrice'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'materialId': materialId,
      'materialName': materialName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice,
    };
  }

  InvoiceItem copyWith({
    String? materialId,
    String? materialName,
    int? quantity,
    double? unitPrice,
    bool clearPrice = false,
  }) {
    return InvoiceItem(
      materialId: materialId ?? this.materialId,
      materialName: materialName ?? this.materialName,
      quantity: quantity ?? this.quantity,
      unitPrice: clearPrice ? null : (unitPrice ?? this.unitPrice),
    );
  }
}

class InvoiceModel {
  const InvoiceModel({
    required this.id,
    this.managerId = '',
    required this.invoiceNumber,
    required this.governorateId,
    required this.governorateName,
    required this.assignmentType,
    this.assignedDelegateId,
    this.assignedDelegateName,
    this.doctorId,
    this.doctorName,
    this.pharmacyId,
    this.pharmacyName,
    this.warehouseId,
    this.warehouseName,
    required this.items,
    required this.totalAmount,
    required this.isPricePending,
    required this.invoiceDate,
    required this.invoiceMonthKey,
    this.notes,
    required this.status,
    this.paidAt,
    this.paidByUid,
    this.paidByName,
    this.paidByRole,
    this.paidFromSource,
    this.deductedManagerMonthKey,
    this.receiptImageUrl,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByRole,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String managerId;
  final String invoiceNumber;
  final String governorateId;
  final String governorateName;
  final InvoiceAssignmentType assignmentType;
  final String? assignedDelegateId;
  final String? assignedDelegateName;
  final String? doctorId;
  final String? doctorName;
  final String? pharmacyId;
  final String? pharmacyName;
  final String? warehouseId;
  final String? warehouseName;
  final List<InvoiceItem> items;
  final double totalAmount;
  final bool isPricePending;
  final DateTime invoiceDate;
  final String invoiceMonthKey; // YYYY-MM
  final String? notes;
  final InvoiceStatus status;
  final DateTime? paidAt;
  final String? paidByUid;
  final String? paidByName;
  final String? paidByRole; // manager | delegate
  final String? paidFromSource; // manager_box | delegate_box
  final String? deductedManagerMonthKey;
  final String? receiptImageUrl;
  final String createdByUid;
  final String createdByName;
  final String createdByRole;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPaid => status == InvoiceStatus.paid;

  /// Effective month key for financial grouping and drill-down:
  /// uses deductedManagerMonthKey when a paid invoice was deducted from a specific month box.
  String get effectiveMonthKey =>
      (isPaid && (deductedManagerMonthKey ?? '').isNotEmpty)
          ? deductedManagerMonthKey!
          : invoiceMonthKey;

  /// Returns the YYYY-MM month key derived directly from [invoiceDate].
  String get invoiceDateMonthKey =>
      '${invoiceDate.year.toString().padLeft(4, '0')}-${invoiceDate.month.toString().padLeft(2, '0')}';

  /// Matches free-text search queries across doctor, pharmacy, warehouse, materials, invoice number, and notes.
  bool matchesSearchQuery(String query) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) return true;
    final tokens =
        normalizedQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final materialsText = items.map((i) => i.materialName).join(' ');
    final haystack = _normalizeSearchText([
      invoiceNumber,
      doctorName,
      pharmacyName,
      warehouseName,
      governorateName,
      assignedDelegateName ?? '',
      notes ?? '',
      materialsText,
    ].join(' '));
    return tokens.every(haystack.contains);
  }

  static String _normalizeSearchText(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
  }

  factory InvoiceModel.fromMap(Map<String, dynamic> map, String id) {
    final rawItems = List<Map<String, dynamic>>.from(map['items'] ?? const []);
    final items = rawItems.map(InvoiceItem.fromMap).toList();
    return InvoiceModel(
      id: id,
      managerId: (map['managerId'] ?? '') as String,
      invoiceNumber: (map['invoiceNumber'] ?? id.substring(0, 6)) as String,
      governorateId: (map['governorateId'] ?? '') as String,
      governorateName: (map['governorateName'] ?? '') as String,
      assignmentType:
          InvoiceAssignmentType.fromString(map['assignmentType'] as String?),
      assignedDelegateId: map['assignedDelegateId'] as String?,
      assignedDelegateName: map['assignedDelegateName'] as String?,
      doctorId: map['doctorId'] as String?,
      doctorName: map['doctorName'] as String?,
      pharmacyId: map['pharmacyId'] as String?,
      pharmacyName: map['pharmacyName'] as String?,
      warehouseId: map['warehouseId'] as String?,
      warehouseName: map['warehouseName'] as String?,
      items: items,
      totalAmount: ((map['totalAmount'] ?? 0) as num).toDouble(),
      isPricePending: (map['isPricePending'] ?? false) as bool,
      invoiceDate:
          (map['invoiceDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      invoiceMonthKey: (map['invoiceMonthKey'] ?? '') as String,
      notes: map['notes'] as String?,
      status: InvoiceStatus.fromString(map['status'] as String?),
      paidAt: (map['paidAt'] as Timestamp?)?.toDate(),
      paidByUid: map['paidByUid'] as String?,
      paidByName: map['paidByName'] as String?,
      paidByRole: map['paidByRole'] as String?,
      paidFromSource: map['paidFromSource'] as String?,
      deductedManagerMonthKey: map['deductedManagerMonthKey'] as String?,
      receiptImageUrl: map['receiptImageUrl'] as String?,
      createdByUid: (map['createdByUid'] ?? '') as String,
      createdByName: (map['createdByName'] ?? '') as String,
      createdByRole: (map['createdByRole'] ?? 'delegate') as String,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap({bool forCreate = false}) {
    return {
      if (managerId.isNotEmpty) 'managerId': managerId,
      'invoiceNumber': invoiceNumber,
      'governorateId': governorateId,
      'governorateName': governorateName,
      'assignmentType': assignmentType.firestoreValue,
      'assignedDelegateId': assignedDelegateId,
      'assignedDelegateName': assignedDelegateName,
      'doctorId': doctorId,
      'doctorName': doctorName,
      'pharmacyId': pharmacyId,
      'pharmacyName': pharmacyName,
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'items': items.map((e) => e.toMap()).toList(),
      'totalAmount': totalAmount,
      'isPricePending': isPricePending,
      'invoiceDate': Timestamp.fromDate(invoiceDate),
      'invoiceMonthKey': invoiceMonthKey,
      'notes': notes,
      'status': status.name,
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      'paidByUid': paidByUid,
      'paidByName': paidByName,
      'paidByRole': paidByRole,
      'paidFromSource': paidFromSource,
      'deductedManagerMonthKey': deductedManagerMonthKey,
      'receiptImageUrl': receiptImageUrl,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdByRole': createdByRole,
      if (forCreate) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
