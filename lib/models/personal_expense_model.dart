import 'package:cloud_firestore/cloud_firestore.dart';

class PersonalExpenseModel {
  const PersonalExpenseModel({
    required this.id,
    this.managerId = '',
    required this.userId,
    required this.userName,
    required this.userRole,
    this.governorateId,
    this.governorateName,
    required this.amount,
    required this.title,
    this.notes,
    this.receiptImageUrl,
    required this.expenseDate,
    required this.monthKey,
    this.deductedManagerMonthKey,
    this.createdAt,
    this.editedByUid,
    this.editedByName,
    this.updatedAt,
  });

  final String id;
  final String managerId;
  final String userId;
  final String userName;
  final String userRole; // manager | delegate
  final String? governorateId;
  final String? governorateName;
  final double amount;
  final String title;
  final String? notes;
  final String? receiptImageUrl;
  final DateTime expenseDate;
  final String monthKey;
  final String? deductedManagerMonthKey;
  final DateTime? createdAt;
  final String? editedByUid;
  final String? editedByName;
  final DateTime? updatedAt;

  bool get isEdited => updatedAt != null || (editedByUid ?? '').isNotEmpty;

  factory PersonalExpenseModel.fromMap(Map<String, dynamic> map, String id) {
    return PersonalExpenseModel(
      id: id,
      managerId: (map['managerId'] ?? '') as String,
      userId: (map['userId'] ?? '') as String,
      userName: (map['userName'] ?? '') as String,
      userRole: (map['userRole'] ?? 'delegate') as String,
      governorateId: map['governorateId'] as String?,
      governorateName: map['governorateName'] as String?,
      amount: ((map['amount'] ?? 0) as num).toDouble(),
      title: (map['title'] ?? '') as String,
      notes: map['notes'] as String?,
      receiptImageUrl: map['receiptImageUrl'] as String?,
      expenseDate:
          (map['expenseDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      monthKey: (map['monthKey'] ?? '') as String,
      deductedManagerMonthKey: map['deductedManagerMonthKey'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      editedByUid: map['editedByUid'] as String?,
      editedByName: map['editedByName'] as String?,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (managerId.isNotEmpty) 'managerId': managerId,
      'userId': userId,
      'userName': userName,
      'userRole': userRole,
      'governorateId': governorateId,
      'governorateName': governorateName,
      'amount': amount,
      'title': title,
      'notes': notes,
      'receiptImageUrl': receiptImageUrl,
      'expenseDate': Timestamp.fromDate(expenseDate),
      'monthKey': monthKey,
      'deductedManagerMonthKey': deductedManagerMonthKey ?? monthKey,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
