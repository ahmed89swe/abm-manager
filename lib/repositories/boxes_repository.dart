import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/services/server_time_service.dart';
import '../models/app_user.dart';
import '../models/monthly_box.dart';
import '../services/audit_helper.dart';
import '../services/notification_service.dart';

class BoxesRepository {
  BoxesRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// ضمان إنشاء صندوق الشهر الحالي تلقائياً عند بدء كل شهر اعتماداً على توقيت السيرفر
  Future<String> ensureCurrentMonthBoxExists(AppUser user) async {
    final now = await ServerTimeService.instance.getTrustedNow();
    final monthKey = ServerTimeService.toMonthKey(now);
    await ensureMonthBoxExists(
      managerId: user.effectiveManagerId,
      monthKey: monthKey,
    );
    return monthKey;
  }

  Future<void> ensureMonthBoxExists({
    required String managerId,
    required String monthKey,
  }) async {
    if (managerId.isEmpty) return;
    final ref = _firestore
        .collection('manager_monthly_boxes')
        .doc(MonthlyBox.docId(managerId, monthKey));
    final doc = await ref.get();
    if (!doc.exists) {
      final parsed = ServerTimeService.parseMonthKey(monthKey);
      await ref.set({
        'managerId': managerId,
        'monthKey': monthKey,
        'year': parsed.year,
        'month': parsed.month,
        'totalCompanyTopUps': 0.0,
        'totalInvoiceDeductions': 0.0,
        'totalExpenseDeductions': 0.0,
        'currentBalance': 0.0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Stream<List<MonthlyBox>> watchMonthlyBoxes(String managerId) {
    if (managerId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('manager_monthly_boxes')
        .where('managerId', isEqualTo: managerId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => MonthlyBox.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.monthKey.compareTo(a.monthKey));
      return list;
    });
  }

  /// متابعة الصناديق الشهرية الفرعية لكل محافظة (للمدير فقط)
  Stream<List<GovernorateMonthlyBox>> watchGovernorateMonthlyBoxes(
    String managerId,
  ) {
    if (managerId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('governorate_monthly_boxes')
        .where('managerId', isEqualTo: managerId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => GovernorateMonthlyBox.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.monthKey.compareTo(a.monthKey));
      return list;
    });
  }

  Stream<List<BoxTransaction>> watchTransactionsForMonth(
    String managerId,
    String monthKey,
  ) {
    if (managerId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('box_transactions')
        .where('managerId', isEqualTo: managerId)
        .where('monthKey', isEqualTo: monthKey)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => BoxTransaction.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) {
        final ta = a.createdAt ?? DateTime(2000);
        final tb = b.createdAt ?? DateTime(2000);
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  Stream<List<BoxTransaction>> watchTransactionsForGovernorateMonth(
    String managerId,
    String governorateId,
    String monthKey,
  ) {
    if (managerId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('box_transactions')
        .where('managerId', isEqualTo: managerId)
        .where('governorateId', isEqualTo: governorateId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => BoxTransaction.fromMap(d.data(), d.id))
          .where((t) => t.monthKey == monthKey)
          .toList();
      list.sort((a, b) {
        final ta = a.createdAt ?? DateTime(2000);
        final tb = b.createdAt ?? DateTime(2000);
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  Stream<List<BoxTransaction>> watchAllBoxTransactions(String managerId) {
    if (managerId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('box_transactions')
        .where('managerId', isEqualTo: managerId)
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => BoxTransaction.fromMap(d.data(), d.id))
            .toList());
  }

  /// تعبئة صندوق شهري من الشركة (للمدير فقط - يدعم تعبئة أي شهر حالي أو سابق)
  Future<void> topUpMonthlyBoxFromCompany({
    required AppUser manager,
    required String monthKey,
    required double amount,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('يجب أن يكون مبلغ التعبئة أكبر من صفر');
    }
    final managerId = manager.effectiveManagerId;
    final parsed = ServerTimeService.parseMonthKey(monthKey);
    final boxRef = _firestore
        .collection('manager_monthly_boxes')
        .doc(MonthlyBox.docId(managerId, monthKey));
    final txRef = _firestore.collection('box_transactions').doc();

    await _firestore.runTransaction((tx) async {
      final boxSnap = await tx.get(boxRef);
      if (!boxSnap.exists) {
        tx.set(boxRef, {
          'managerId': managerId,
          'monthKey': monthKey,
          'year': parsed.year,
          'month': parsed.month,
          'totalCompanyTopUps': amount,
          'totalInvoiceDeductions': 0.0,
          'totalExpenseDeductions': 0.0,
          'currentBalance': amount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final data = boxSnap.data()!;
        final prevTopUp = ((data['totalCompanyTopUps'] ?? 0) as num).toDouble();
        final prevBalance = ((data['currentBalance'] ?? 0) as num).toDouble();
        tx.update(boxRef, {
          'totalCompanyTopUps': prevTopUp + amount,
          'currentBalance': prevBalance + amount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      tx.set(txRef, {
        'managerId': managerId,
        'type': BoxTransactionType.companyTopUp.firestoreValue,
        'monthKey': monthKey,
        'amount': amount,
        'performedByUid': manager.uid,
        'performedByName': manager.name,
        'performedByRole': manager.role.value,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: manager,
      actionType: 'company_topup',
      descriptionAr: 'تعبئة صندوق شهر $monthKey من الشركة بمبلغ $amount',
      descriptionEn: 'Company top-up for Month $monthKey: $amount',
      metadata: {'monthKey': monthKey, 'amount': amount, 'notes': notes},
    );

    await NotificationService.instance.sendCloudNotification(
      managerId: managerId,
      titleAr: 'تعبئة صندوق شهري',
      titleEn: 'Monthly Box Topped Up',
      bodyAr: 'تمت تعبئة صندوق شهر $monthKey بمبلغ $amount',
      bodyEn: 'Month $monthKey box topped up with $amount',
      type: 'company_topup',
      targetRole: 'manager',
      audienceTags: ['MANAGER_$managerId'],
      referenceId: monthKey,
      createdByUid: manager.uid,
    );
  }

  /// تعديل عملية تعبئة من الشركة (تعديل المبلغ و/أو الشهر و/أو الملاحظات)
  Future<void> editCompanyTopUp({
    required AppUser manager,
    required BoxTransaction oldTx,
    required String newMonthKey,
    required double newAmount,
    String? notes,
  }) async {
    if (!manager.isManager) {
      throw StateError('تعديل عمليات التعبئة متاح للمدير فقط');
    }
    if (oldTx.type != BoxTransactionType.companyTopUp) {
      throw ArgumentError('يمكن تعديل عمليات التعبئة من الشركة فقط');
    }
    if (newAmount <= 0) {
      throw ArgumentError('يجب أن يكون مبلغ التعبئة أكبر من صفر');
    }

    final managerId = manager.effectiveManagerId;
    final txRef = _firestore.collection('box_transactions').doc(oldTx.id);
    String actualOldMonthKey = oldTx.monthKey;
    double actualOldAmount = oldTx.amount;

    await _firestore.runTransaction((tx) async {
      final txSnap = await tx.get(txRef);
      if (!txSnap.exists || txSnap.data() == null) {
        throw StateError('عملية التعبئة غير موجودة');
      }
      final txData = txSnap.data()!;
      if (txData['type'] != BoxTransactionType.companyTopUp.firestoreValue) {
        throw StateError('نوع العملية غير صالح للتعديل');
      }
      actualOldMonthKey = (txData['monthKey'] as String?) ?? oldTx.monthKey;
      actualOldAmount =
          ((txData['amount'] ?? oldTx.amount) as num).toDouble();

      final newParsed = ServerTimeService.parseMonthKey(newMonthKey);
      final newBoxRef = _firestore
          .collection('manager_monthly_boxes')
          .doc(MonthlyBox.docId(managerId, newMonthKey));

      if (actualOldMonthKey == newMonthKey) {
        final delta = newAmount - actualOldAmount;
        final newBoxSnap = await tx.get(newBoxRef);
        if (!newBoxSnap.exists) {
          tx.set(newBoxRef, {
            'managerId': managerId,
            'monthKey': newMonthKey,
            'year': newParsed.year,
            'month': newParsed.month,
            'totalCompanyTopUps': newAmount,
            'totalInvoiceDeductions': 0.0,
            'totalExpenseDeductions': 0.0,
            'currentBalance': newAmount,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final bData = newBoxSnap.data()!;
          final prevTopUp =
              ((bData['totalCompanyTopUps'] ?? 0) as num).toDouble();
          final prevBalance =
              ((bData['currentBalance'] ?? 0) as num).toDouble();
          tx.update(newBoxRef, {
            'totalCompanyTopUps': prevTopUp + delta,
            'currentBalance': prevBalance + delta,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        final oldBoxRef = _firestore
            .collection('manager_monthly_boxes')
            .doc(MonthlyBox.docId(managerId, actualOldMonthKey));
        final oldBoxSnap = await tx.get(oldBoxRef);
        final newBoxSnap = await tx.get(newBoxRef);

        if (oldBoxSnap.exists) {
          final oldData = oldBoxSnap.data()!;
          final prevOldTopUp =
              ((oldData['totalCompanyTopUps'] ?? 0) as num).toDouble();
          final prevOldBal =
              ((oldData['currentBalance'] ?? 0) as num).toDouble();
          tx.update(oldBoxRef, {
            'totalCompanyTopUps': prevOldTopUp - actualOldAmount,
            'currentBalance': prevOldBal - actualOldAmount,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        if (!newBoxSnap.exists) {
          tx.set(newBoxRef, {
            'managerId': managerId,
            'monthKey': newMonthKey,
            'year': newParsed.year,
            'month': newParsed.month,
            'totalCompanyTopUps': newAmount,
            'totalInvoiceDeductions': 0.0,
            'totalExpenseDeductions': 0.0,
            'currentBalance': newAmount,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final newData = newBoxSnap.data()!;
          final prevNewTopUp =
              ((newData['totalCompanyTopUps'] ?? 0) as num).toDouble();
          final prevNewBal =
              ((newData['currentBalance'] ?? 0) as num).toDouble();
          tx.update(newBoxRef, {
            'totalCompanyTopUps': prevNewTopUp + newAmount,
            'currentBalance': prevNewBal + newAmount,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      tx.update(txRef, {
        'monthKey': newMonthKey,
        'amount': newAmount,
        'notes': (notes != null && notes.trim().isNotEmpty) ? notes.trim() : null,
        'editedByUid': manager.uid,
        'editedByName': manager.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: manager,
      actionType: 'edit_company_topup',
      descriptionAr:
          'عدّل المدير عملية التعبئة من الشركة ($actualOldMonthKey: $actualOldAmount -> $newMonthKey: $newAmount)',
      descriptionEn:
          'Manager edited company top-up ($actualOldMonthKey: $actualOldAmount -> $newMonthKey: $newAmount)',
      metadata: {
        'transactionId': oldTx.id,
        'oldMonthKey': actualOldMonthKey,
        'newMonthKey': newMonthKey,
        'oldAmount': actualOldAmount,
        'newAmount': newAmount,
      },
    );

    await NotificationService.instance.sendCloudNotification(
      managerId: managerId,
      titleAr: 'تعديل تعبئة من الشركة',
      titleEn: 'Company Top-Up Edited',
      bodyAr:
          'تم تعديل عملية التعبئة لشهر $newMonthKey إلى مبلغ $newAmount',
      bodyEn: 'Company top-up for $newMonthKey updated to $newAmount',
      type: 'edit_company_topup',
      targetRole: 'manager',
      audienceTags: ['MANAGER_$managerId'],
      referenceId: oldTx.id,
      createdByUid: manager.uid,
    );
  }

  /// تعبئة صندوق فرعي شهري لمحافظة معينة (يدعم الأشهر الحالية والسابقة)
  Future<void> topUpGovernorateMonthlyBox({
    required AppUser manager,
    required String governorateId,
    required String governorateName,
    required String monthKey,
    required double amount,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('يجب أن يكون مبلغ التعبئة أكبر من صفر');
    }
    final managerId = manager.effectiveManagerId;
    final parsed = ServerTimeService.parseMonthKey(monthKey);
    final docId =
        GovernorateMonthlyBox.docId(managerId, governorateId, monthKey);
    final govBoxRef =
        _firestore.collection('governorate_monthly_boxes').doc(docId);
    final txRef = _firestore.collection('box_transactions').doc();

    await _firestore.runTransaction((tx) async {
      final boxSnap = await tx.get(govBoxRef);
      if (!boxSnap.exists) {
        tx.set(govBoxRef, {
          'managerId': managerId,
          'governorateId': governorateId,
          'governorateName': governorateName,
          'monthKey': monthKey,
          'year': parsed.year,
          'month': parsed.month,
          'totalTopUps': amount,
          'totalInvoiceDeductions': 0.0,
          'totalExpenseDeductions': 0.0,
          'currentBalance': amount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final data = boxSnap.data()!;
        final prevTopUp = ((data['totalTopUps'] ?? 0) as num).toDouble();
        final prevBalance = ((data['currentBalance'] ?? 0) as num).toDouble();
        tx.update(govBoxRef, {
          'governorateName': governorateName,
          'totalTopUps': prevTopUp + amount,
          'currentBalance': prevBalance + amount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      tx.set(txRef, {
        'managerId': managerId,
        'type': BoxTransactionType.governorateTopUp.firestoreValue,
        'monthKey': monthKey,
        'amount': amount,
        'governorateId': governorateId,
        'governorateName': governorateName,
        'performedByUid': manager.uid,
        'performedByName': manager.name,
        'performedByRole': manager.role.value,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: manager,
      actionType: 'governorate_topup',
      descriptionAr:
          'تعبئة الصندوق الفرعي لمحافظة $governorateName ($monthKey) بمبلغ $amount',
      descriptionEn:
          'Topped up $governorateName sub-box ($monthKey) with $amount',
      metadata: {
        'governorateId': governorateId,
        'monthKey': monthKey,
        'amount': amount,
        'notes': notes,
      },
    );

    await NotificationService.instance.sendCloudNotification(
      managerId: managerId,
      titleAr: 'تعبئة صندوق محافظة',
      titleEn: 'Governorate Box Topped Up',
      bodyAr:
          'تمت تعبئة صندوق محافظة $governorateName لشهر $monthKey بمبلغ $amount',
      bodyEn:
          '$governorateName sub-box for $monthKey topped up with $amount',
      type: 'governorate_topup',
      targetRole: 'manager',
      audienceTags: ['MANAGER_$managerId'],
      referenceId: docId,
      createdByUid: manager.uid,
    );
  }

  /// تعبئة الصندوق الفرعي الافتراضي الخاص بمندوب (لا يغير صندوق المدير إلا عند الصرف الفعلي)
  Future<void> topUpDelegateVirtualBox({
    required AppUser manager,
    required AppUser delegate,
    required double amount,
    String? monthKeyOverride,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('يجب أن يكون مبلغ التعبئة أكبر من صفر');
    }
    final managerId = manager.effectiveManagerId;
    final now = await ServerTimeService.instance.getTrustedNow();
    final monthKey = monthKeyOverride ?? ServerTimeService.toMonthKey(now);
    final delegateRef = _firestore.collection('users').doc(delegate.uid);
    final txRef = _firestore.collection('box_transactions').doc();

    await _firestore.runTransaction((tx) async {
      final delegateSnap = await tx.get(delegateRef);
      if (!delegateSnap.exists) {
        throw StateError('حساب المندوب غير موجود');
      }
      final prevBalance =
          ((delegateSnap.data()!['virtualBoxBalance'] ?? 0) as num).toDouble();
      tx.update(delegateRef, {
        'virtualBoxBalance': prevBalance + amount,
      });

      tx.set(txRef, {
        'managerId': managerId,
        'type': BoxTransactionType.delegateVirtualTopUp.firestoreValue,
        'monthKey': monthKey,
        'amount': amount,
        'delegateId': delegate.uid,
        'delegateName': delegate.name,
        'governorateId': delegate.governorateId,
        'governorateName': delegate.governorateName,
        'performedByUid': manager.uid,
        'performedByName': manager.name,
        'performedByRole': manager.role.value,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: manager,
      actionType: 'delegate_topup',
      descriptionAr:
          'تعبئة الصندوق الافتراضي للمندوب ${delegate.name} ($monthKey) بمبلغ $amount',
      descriptionEn:
          'Topped up delegate ${delegate.name} virtual box ($monthKey) by $amount',
      metadata: {
        'delegateId': delegate.uid,
        'monthKey': monthKey,
        'amount': amount,
        'notes': notes,
      },
    );

    await NotificationService.instance.sendCloudNotification(
      managerId: managerId,
      titleAr: 'تمت تعبئة صندوقك',
      titleEn: 'Your Box Was Topped Up',
      bodyAr: 'أضاف المدير مبلغ $amount إلى رصيد صندوقك الافتراضي ($monthKey)',
      bodyEn: 'Manager added $amount to your virtual box balance ($monthKey)',
      type: 'delegate_topup',
      targetRole: 'delegate',
      audienceTags: ['MANAGER_$managerId', 'USER_${delegate.uid}'],
      targetUserIds: [delegate.uid],
      referenceId: delegate.uid,
      createdByUid: manager.uid,
    );
  }
}
