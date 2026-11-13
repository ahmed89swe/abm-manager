import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyBox {
  const MonthlyBox({
    this.id = '',
    this.managerId = '',
    required this.monthKey,
    required this.year,
    required this.month,
    required this.totalCompanyTopUps,
    required this.totalInvoiceDeductions,
    required this.totalExpenseDeductions,
    required this.currentBalance,
    this.updatedAt,
  });

  final String id; // {managerId}_{YYYY-MM}
  final String managerId;
  final String monthKey; // YYYY-MM
  final int year;
  final int month;
  final double totalCompanyTopUps;
  final double totalInvoiceDeductions;
  final double totalExpenseDeductions;
  final double currentBalance; // يقبل القيم السالبة عند تأخر تعبئة الشركة
  final DateTime? updatedAt;

  static String docId(String managerId, String monthKey) =>
      managerId.isNotEmpty ? '${managerId}_$monthKey' : monthKey;

  double get totalDeductions =>
      totalInvoiceDeductions + totalExpenseDeductions;

  String label(bool isAr) =>
      isAr ? 'صندوق شهر $month ($year)' : 'Month $month Box ($year)';

  String shortLabel(bool isAr) => isAr ? 'شهر $month' : 'Month $month';

  factory MonthlyBox.empty(String monthKey, {String managerId = ''}) {
    final parts = monthKey.split('-');
    final year = int.tryParse(parts.first) ?? DateTime.now().year;
    final month =
        parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : DateTime.now().month;
    return MonthlyBox(
      id: docId(managerId, monthKey),
      managerId: managerId,
      monthKey: monthKey,
      year: year,
      month: month,
      totalCompanyTopUps: 0,
      totalInvoiceDeductions: 0,
      totalExpenseDeductions: 0,
      currentBalance: 0,
    );
  }

  factory MonthlyBox.fromMap(Map<String, dynamic> map, String id) {
    final rawKey = (map['monthKey'] as String?) ?? '';
    final resolvedMonthKey =
        rawKey.isNotEmpty ? rawKey : (id.contains('_') ? id.split('_').last : id);
    return MonthlyBox(
      id: id,
      managerId: (map['managerId'] ?? '') as String,
      monthKey: resolvedMonthKey,
      year: (map['year'] ?? 2026) as int,
      month: (map['month'] ?? 1) as int,
      totalCompanyTopUps: ((map['totalCompanyTopUps'] ?? 0) as num).toDouble(),
      totalInvoiceDeductions:
          ((map['totalInvoiceDeductions'] ?? 0) as num).toDouble(),
      totalExpenseDeductions:
          ((map['totalExpenseDeductions'] ?? 0) as num).toDouble(),
      currentBalance: ((map['currentBalance'] ?? 0) as num).toDouble(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (managerId.isNotEmpty) 'managerId': managerId,
      'monthKey': monthKey,
      'year': year,
      'month': month,
      'totalCompanyTopUps': totalCompanyTopUps,
      'totalInvoiceDeductions': totalInvoiceDeductions,
      'totalExpenseDeductions': totalExpenseDeductions,
      'currentBalance': currentBalance,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

/// صندوق فرعي خاص بكل محافظة ويتضمن أشهرها (فصل المحافظات عن بعضها)
class GovernorateMonthlyBox {
  const GovernorateMonthlyBox({
    required this.id,
    this.managerId = '',
    required this.governorateId,
    required this.governorateName,
    required this.monthKey,
    required this.year,
    required this.month,
    required this.totalTopUps,
    required this.totalInvoiceDeductions,
    required this.totalExpenseDeductions,
    required this.currentBalance,
    this.updatedAt,
  });

  final String id; // {managerId}_{governorateId}_{YYYY-MM}
  final String managerId;
  final String governorateId;
  final String governorateName;
  final String monthKey;
  final int year;
  final int month;
  final double totalTopUps;
  final double totalInvoiceDeductions;
  final double totalExpenseDeductions;
  final double currentBalance;
  final DateTime? updatedAt;

  double get totalDeductions =>
      totalInvoiceDeductions + totalExpenseDeductions;

  String label(bool isAr) =>
      isAr ? 'صندوق شهر $month ($year)' : 'Month $month Box ($year)';

  static String legacyDocId(String governorateId, String monthKey) =>
      '${governorateId}_$monthKey';

  static String docId(
    String managerId,
    String governorateId,
    String monthKey,
  ) =>
      managerId.isNotEmpty
          ? '${managerId}_${governorateId}_$monthKey'
          : '${governorateId}_$monthKey';

  factory GovernorateMonthlyBox.empty({
    String managerId = '',
    required String governorateId,
    required String governorateName,
    required String monthKey,
  }) {
    final parts = monthKey.split('-');
    final year = int.tryParse(parts.first) ?? DateTime.now().year;
    final month =
        parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : DateTime.now().month;
    return GovernorateMonthlyBox(
      id: docId(managerId, governorateId, monthKey),
      managerId: managerId,
      governorateId: governorateId,
      governorateName: governorateName,
      monthKey: monthKey,
      year: year,
      month: month,
      totalTopUps: 0,
      totalInvoiceDeductions: 0,
      totalExpenseDeductions: 0,
      currentBalance: 0,
    );
  }

  factory GovernorateMonthlyBox.fromMap(Map<String, dynamic> map, String id) {
    return GovernorateMonthlyBox(
      id: id,
      managerId: (map['managerId'] ?? '') as String,
      governorateId: (map['governorateId'] ?? '') as String,
      governorateName: (map['governorateName'] ?? '') as String,
      monthKey: (map['monthKey'] ?? '') as String,
      year: (map['year'] ?? 2026) as int,
      month: (map['month'] ?? 1) as int,
      totalTopUps: ((map['totalTopUps'] ?? 0) as num).toDouble(),
      totalInvoiceDeductions:
          ((map['totalInvoiceDeductions'] ?? 0) as num).toDouble(),
      totalExpenseDeductions:
          ((map['totalExpenseDeductions'] ?? 0) as num).toDouble(),
      currentBalance: ((map['currentBalance'] ?? 0) as num).toDouble(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

enum BoxTransactionType {
  companyTopUp,
  governorateTopUp,
  delegateVirtualTopUp,
  invoicePayment,
  personalExpense,
  invoiceEditAdjustment;

  static BoxTransactionType fromString(String? value) {
    switch (value) {
      case 'company_topup':
        return BoxTransactionType.companyTopUp;
      case 'governorate_topup':
        return BoxTransactionType.governorateTopUp;
      case 'delegate_virtual_topup':
        return BoxTransactionType.delegateVirtualTopUp;
      case 'invoice_payment':
        return BoxTransactionType.invoicePayment;
      case 'personal_expense':
        return BoxTransactionType.personalExpense;
      case 'invoice_edit_adjustment':
        return BoxTransactionType.invoiceEditAdjustment;
      default:
        return BoxTransactionType.invoicePayment;
    }
  }

  String get firestoreValue {
    switch (this) {
      case BoxTransactionType.companyTopUp:
        return 'company_topup';
      case BoxTransactionType.governorateTopUp:
        return 'governorate_topup';
      case BoxTransactionType.delegateVirtualTopUp:
        return 'delegate_virtual_topup';
      case BoxTransactionType.invoicePayment:
        return 'invoice_payment';
      case BoxTransactionType.personalExpense:
        return 'personal_expense';
      case BoxTransactionType.invoiceEditAdjustment:
        return 'invoice_edit_adjustment';
    }
  }
}

class BoxTransaction {
  const BoxTransaction({
    required this.id,
    this.managerId = '',
    required this.type,
    required this.monthKey,
    required this.amount,
    required this.performedByUid,
    required this.performedByName,
    required this.performedByRole,
    this.delegateId,
    this.delegateName,
    this.governorateId,
    this.governorateName,
    this.referenceId,
    this.notes,
    this.createdAt,
    this.editedByUid,
    this.editedByName,
    this.updatedAt,
  });

  final String id;
  final String managerId;
  final BoxTransactionType type;
  final String monthKey;
  final double amount;
  final String performedByUid;
  final String performedByName;
  final String performedByRole;
  final String? delegateId;
  final String? delegateName;
  final String? governorateId;
  final String? governorateName;
  final String? referenceId;
  final String? notes;
  final DateTime? createdAt;
  final String? editedByUid;
  final String? editedByName;
  final DateTime? updatedAt;

  bool get isEdited => updatedAt != null;

  factory BoxTransaction.fromMap(Map<String, dynamic> map, String id) {
    return BoxTransaction(
      id: id,
      managerId: (map['managerId'] ?? '') as String,
      type: BoxTransactionType.fromString(map['type'] as String?),
      monthKey: (map['monthKey'] ?? '') as String,
      amount: ((map['amount'] ?? 0) as num).toDouble(),
      performedByUid: (map['performedByUid'] ?? '') as String,
      performedByName: (map['performedByName'] ?? '') as String,
      performedByRole: (map['performedByRole'] ?? 'manager') as String,
      delegateId: map['delegateId'] as String?,
      delegateName: map['delegateName'] as String?,
      governorateId: map['governorateId'] as String?,
      governorateName: map['governorateName'] as String?,
      referenceId: map['referenceId'] as String?,
      notes: map['notes'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      editedByUid: map['editedByUid'] as String?,
      editedByName: map['editedByName'] as String?,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (managerId.isNotEmpty) 'managerId': managerId,
      'type': type.firestoreValue,
      'monthKey': monthKey,
      'amount': amount,
      'performedByUid': performedByUid,
      'performedByName': performedByName,
      'performedByRole': performedByRole,
      'delegateId': delegateId,
      'delegateName': delegateName,
      'governorateId': governorateId,
      'governorateName': governorateName,
      'referenceId': referenceId,
      'notes': notes,
      if (editedByUid != null) 'editedByUid': editedByUid,
      if (editedByName != null) 'editedByName': editedByName,
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }
}
