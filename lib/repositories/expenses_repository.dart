import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/services/server_time_service.dart';
import '../models/app_user.dart';
import '../models/monthly_box.dart';
import '../models/personal_expense_model.dart';
import '../services/audit_helper.dart';
import '../services/notification_service.dart';
import '../services/receipt_storage_service.dart';

class ExpensesRepository {
  ExpensesRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<PersonalExpenseModel>> watchExpensesForUser(AppUser user) {
    final managerId = user.effectiveManagerId;
    if (managerId.isEmpty) return Stream.value(const []);
    Query<Map<String, dynamic>> query = _firestore
        .collection('personal_expenses')
        .where('managerId', isEqualTo: managerId);
    if (user.isDelegate) {
      query = query.where('userId', isEqualTo: user.uid);
    }
    return query.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => PersonalExpenseModel.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
      return list;
    });
  }

  /// إضافة مصروف شخصي للمدير أو المندوب واستقطاعه من الرصيد في الشهر المقابل
  Future<void> addPersonalExpense({
    required AppUser actor,
    required double amount,
    required String title,
    String? notes,
    DateTime? managerSelectedDate,
    String? managerDeductMonthKey,
    String? managerGovernorateId,
    String? managerGovernorateName,
    PickedImageData? receiptImage,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('يجب أن يكون مبلغ المصروف أكبر من صفر');
    }

    final trustedNow = await ServerTimeService.instance.getTrustedNow();
    final effectiveDate =
        actor.isManager ? (managerSelectedDate ?? trustedNow) : trustedNow;
    final monthKey = ServerTimeService.toMonthKey(effectiveDate);
    final deductMonthKey =
        actor.isManager ? (managerDeductMonthKey ?? monthKey) : monthKey;

    final String? effectiveGovId = actor.isManager
        ? ((managerGovernorateId != null && managerGovernorateId.isNotEmpty)
            ? managerGovernorateId
            : null)
        : ((actor.governorateId != null && actor.governorateId!.isNotEmpty)
            ? actor.governorateId
            : null);
    final String? effectiveGovName = actor.isManager
        ? (effectiveGovId != null ? managerGovernorateName : null)
        : actor.governorateName;
    final hasGov = effectiveGovId != null && effectiveGovId.isNotEmpty;

    final expenseRef = _firestore.collection('personal_expenses').doc();
    String? receiptUrl;
    if (receiptImage != null) {
      try {
        receiptUrl = await ReceiptStorageService.instance.uploadReceipt(
          image: receiptImage,
          folder: 'receipts/expenses',
          referenceId: expenseRef.id,
        );
      } catch (_) {}
    }

    final managerId = actor.effectiveManagerId;
    final monthBoxRef = _firestore
        .collection('manager_monthly_boxes')
        .doc(MonthlyBox.docId(managerId, deductMonthKey));
    final govBoxRef = hasGov
        ? _firestore.collection('governorate_monthly_boxes').doc(
              GovernorateMonthlyBox.docId(
                managerId,
                effectiveGovId,
                deductMonthKey,
              ),
            )
        : null;
    final txRef = _firestore.collection('box_transactions').doc();
    final userRef = _firestore.collection('users').doc(actor.uid);

    await _firestore.runTransaction((tx) async {
      DocumentSnapshot<Map<String, dynamic>>? monthBoxSnap;
      DocumentSnapshot<Map<String, dynamic>>? govBoxSnap;
      DocumentSnapshot<Map<String, dynamic>>? delegateSnap;

      if (actor.isManager) {
        monthBoxSnap = await tx.get(monthBoxRef);
        if (govBoxRef != null) {
          govBoxSnap = await tx.get(govBoxRef);
        }
      } else {
        delegateSnap = await tx.get(userRef);
      }

      if (actor.isManager) {
        _applyManagerMonthBoxDelta(
          tx: tx,
          ref: monthBoxRef,
          snap: monthBoxSnap,
          managerId: managerId,
          monthKey: deductMonthKey,
          amountDelta: amount,
        );
        if (govBoxRef != null && hasGov) {
          _applyGovBoxDelta(
            tx: tx,
            ref: govBoxRef,
            snap: govBoxSnap,
            managerId: managerId,
            governorateId: effectiveGovId,
            governorateName: effectiveGovName ?? '',
            monthKey: deductMonthKey,
            amountDelta: amount,
          );
        }
      } else {
        _blindIncrementBoxesForDelegate(
          tx: tx,
          managerId: managerId,
          deductMonthKey: deductMonthKey,
          governorateId: effectiveGovId,
          governorateName: effectiveGovName,
          amountDelta: amount,
        );
      }

      if (actor.isDelegate && delegateSnap != null && delegateSnap.exists) {
        final prevBal =
            ((delegateSnap.data()!['virtualBoxBalance'] ?? 0) as num)
                .toDouble();
        tx.update(userRef, {
          'virtualBoxBalance': prevBal - amount,
        });
      }

      final cleanNotes =
          (notes?.trim().isNotEmpty ?? false) ? notes!.trim() : null;
      final expense = PersonalExpenseModel(
        id: expenseRef.id,
        managerId: managerId,
        userId: actor.uid,
        userName: actor.name,
        userRole: actor.role.value,
        governorateId: effectiveGovId,
        governorateName: effectiveGovName,
        amount: amount,
        title: title.trim(),
        notes: cleanNotes,
        receiptImageUrl: receiptUrl,
        expenseDate: effectiveDate,
        monthKey: monthKey,
        deductedManagerMonthKey: deductMonthKey,
      );

      tx.set(expenseRef, expense.toMap());
      tx.set(txRef, {
        'managerId': managerId,
        'type': BoxTransactionType.personalExpense.firestoreValue,
        'monthKey': deductMonthKey,
        'amount': amount,
        'delegateId': actor.isDelegate ? actor.uid : null,
        'delegateName': actor.isDelegate ? actor.name : null,
        'governorateId': effectiveGovId,
        'governorateName': effectiveGovName,
        'performedByUid': actor.uid,
        'performedByName': actor.name,
        'performedByRole': actor.role.value,
        'referenceId': expenseRef.id,
        'notes': 'مصروف شخصي: ${title.trim()}',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: actor,
      actionType: 'personal_expense',
      descriptionAr:
          'سجّل ${actor.name} مصروفاً شخصياً ($title) بمبلغ $amount',
      descriptionEn:
          '${actor.name} recorded personal expense ($title): $amount',
      metadata: {
        'expenseId': expenseRef.id,
        'amount': amount,
        'monthKey': deductMonthKey,
        'governorateId': ?effectiveGovId,
      },
    );

    await NotificationService.instance.sendCloudNotification(
      managerId: managerId,
      titleAr: 'مصروف شخصي جديد',
      titleEn: 'New Personal Expense',
      bodyAr: 'سجل ${actor.name} مصروفاً ($title) بمبلغ $amount',
      bodyEn: '${actor.name} added personal expense ($title): $amount',
      type: 'personal_expense',
      targetRole: 'manager',
      audienceTags: actor.isDelegate
          ? ['MANAGER_$managerId', 'USER_${actor.uid}']
          : ['MANAGER_$managerId'],
      targetUserIds: actor.isDelegate ? [actor.uid] : const [],
      referenceId: expenseRef.id,
      createdByUid: actor.uid,
    );
  }

  /// تعديل مصروف شخصي (المدير يعدل كافة الحقول والشهر والمحافظة، والمندوب يعدل مصروفه الخاص)
  Future<void> editPersonalExpense({
    required AppUser actor,
    required PersonalExpenseModel original,
    required double newAmount,
    required String title,
    String? notes,
    DateTime? managerSelectedDate,
    String? managerDeductMonthKey,
    String? managerGovernorateId,
    String? managerGovernorateName,
    PickedImageData? newReceiptImage,
    bool removeReceipt = false,
  }) async {
    if (newAmount <= 0) {
      throw ArgumentError('يجب أن يكون مبلغ المصروف أكبر من صفر');
    }
    final managerId = actor.effectiveManagerId;
    if (original.managerId != managerId) {
      throw StateError('لا يمكن تعديل مصروف خارج نطاق حسابك');
    }
    if (!actor.isManager && original.userId != actor.uid) {
      throw StateError('غير مسموح بتعديل مصروف لمندوب آخر');
    }

    String? receiptUrl = removeReceipt ? null : original.receiptImageUrl;
    if (newReceiptImage != null) {
      try {
        receiptUrl = await ReceiptStorageService.instance.uploadReceipt(
          image: newReceiptImage,
          folder: 'receipts/expenses',
          referenceId:
              '${original.id}_${DateTime.now().millisecondsSinceEpoch}',
        );
      } catch (_) {}
    }

    final oldMonthKey = (original.deductedManagerMonthKey ?? '').isNotEmpty
        ? original.deductedManagerMonthKey!
        : original.monthKey;
    final oldGovId =
        (original.governorateId != null && original.governorateId!.isNotEmpty)
            ? original.governorateId
            : null;
    final cleanNotes =
        (notes?.trim().isNotEmpty ?? false) ? notes!.trim() : null;
    final expenseRef =
        _firestore.collection('personal_expenses').doc(original.id);

    if (actor.isManager) {
      final newDate = managerSelectedDate ?? original.expenseDate;
      final newDateMonthKey = ServerTimeService.toMonthKey(newDate);
      final newMonthKey = (managerDeductMonthKey != null &&
              managerDeductMonthKey.isNotEmpty)
          ? managerDeductMonthKey
          : oldMonthKey;
      final String? newGovId =
          (managerGovernorateId != null && managerGovernorateId.isNotEmpty)
              ? managerGovernorateId
              : null;
      final String? newGovName =
          newGovId != null ? managerGovernorateName : null;

      // جلب حركات الصندوق المرتبطة قبل الترانزكشن
      final txQuery = await _firestore
          .collection('box_transactions')
          .where('managerId', isEqualTo: managerId)
          .where('referenceId', isEqualTo: original.id)
          .get();
      final matchingTxRefs = txQuery.docs
          .where((d) =>
              d.data()['type'] ==
              BoxTransactionType.personalExpense.firestoreValue)
          .map((d) => d.reference)
          .toList();

      await _firestore.runTransaction((tx) async {
        // 1. جميع القراءات قبل أي كتابة
        final oldMonthRef = _firestore
            .collection('manager_monthly_boxes')
            .doc(MonthlyBox.docId(managerId, oldMonthKey));
        final newMonthRef = _firestore
            .collection('manager_monthly_boxes')
            .doc(MonthlyBox.docId(managerId, newMonthKey));
        final oldMonthSnap = await tx.get(oldMonthRef);
        final newMonthSnap =
            newMonthKey == oldMonthKey ? oldMonthSnap : await tx.get(newMonthRef);

        DocumentReference<Map<String, dynamic>>? oldGovRef;
        DocumentSnapshot<Map<String, dynamic>>? oldGovSnap;
        if (oldGovId != null) {
          oldGovRef = _firestore
              .collection('governorate_monthly_boxes')
              .doc(GovernorateMonthlyBox.docId(managerId, oldGovId, oldMonthKey));
          oldGovSnap = await tx.get(oldGovRef);
        }

        DocumentReference<Map<String, dynamic>>? newGovRef;
        DocumentSnapshot<Map<String, dynamic>>? newGovSnap;
        final sameGovBox = oldGovId != null &&
            oldGovId == newGovId &&
            oldMonthKey == newMonthKey;
        if (newGovId != null) {
          if (sameGovBox) {
            newGovRef = oldGovRef;
            newGovSnap = oldGovSnap;
          } else {
            newGovRef = _firestore
                .collection('governorate_monthly_boxes')
                .doc(GovernorateMonthlyBox.docId(
                    managerId, newGovId, newMonthKey));
            newGovSnap = await tx.get(newGovRef);
          }
        }

        DocumentReference<Map<String, dynamic>>? ownerRef;
        DocumentSnapshot<Map<String, dynamic>>? ownerSnap;
        if (original.userRole == 'delegate' && original.userId.isNotEmpty) {
          ownerRef = _firestore.collection('users').doc(original.userId);
          ownerSnap = await tx.get(ownerRef);
        }

        // 2. تعديل الصندوق الشهري العام
        if (oldMonthKey == newMonthKey) {
          _applyManagerMonthBoxDelta(
            tx: tx,
            ref: oldMonthRef,
            snap: oldMonthSnap,
            managerId: managerId,
            monthKey: oldMonthKey,
            amountDelta: newAmount - original.amount,
          );
        } else {
          _applyManagerMonthBoxDelta(
            tx: tx,
            ref: oldMonthRef,
            snap: oldMonthSnap,
            managerId: managerId,
            monthKey: oldMonthKey,
            amountDelta: -original.amount,
          );
          _applyManagerMonthBoxDelta(
            tx: tx,
            ref: newMonthRef,
            snap: newMonthSnap,
            managerId: managerId,
            monthKey: newMonthKey,
            amountDelta: newAmount,
          );
        }

        // 3. تعديل صندوق المحافظة الفرعي
        if (sameGovBox && oldGovRef != null) {
          _applyGovBoxDelta(
            tx: tx,
            ref: oldGovRef,
            snap: oldGovSnap,
            managerId: managerId,
            governorateId: oldGovId,
            governorateName:
                newGovName ?? original.governorateName ?? '',
            monthKey: oldMonthKey,
            amountDelta: newAmount - original.amount,
          );
        } else {
          if (oldGovRef != null && oldGovId != null) {
            _applyGovBoxDelta(
              tx: tx,
              ref: oldGovRef,
              snap: oldGovSnap,
              managerId: managerId,
              governorateId: oldGovId,
              governorateName: original.governorateName ?? '',
              monthKey: oldMonthKey,
              amountDelta: -original.amount,
            );
          }
          if (newGovRef != null && newGovId != null) {
            _applyGovBoxDelta(
              tx: tx,
              ref: newGovRef,
              snap: newGovSnap,
              managerId: managerId,
              governorateId: newGovId,
              governorateName: newGovName ?? '',
              monthKey: newMonthKey,
              amountDelta: newAmount,
            );
          }
        }

        // 4. تعديل الرصيد الافتراضي للمندوب صاحب المصروف إن وجد
        final amountDelta = newAmount - original.amount;
        if (ownerRef != null &&
            ownerSnap != null &&
            ownerSnap.exists &&
            amountDelta != 0) {
          final prevBal =
              ((ownerSnap.data()!['virtualBoxBalance'] ?? 0) as num).toDouble();
          tx.update(ownerRef, {
            'virtualBoxBalance': prevBal - amountDelta,
          });
        }

        // 5. تحديث سجل المصروف والحركة المالية
        tx.update(expenseRef, {
          'title': title.trim(),
          'amount': newAmount,
          'notes': cleanNotes,
          'receiptImageUrl': receiptUrl,
          'governorateId': newGovId,
          'governorateName': newGovName,
          'expenseDate': Timestamp.fromDate(newDate),
          'monthKey': newDateMonthKey,
          'deductedManagerMonthKey': newMonthKey,
          'editedByUid': actor.uid,
          'editedByName': actor.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        for (final txDocRef in matchingTxRefs) {
          tx.update(txDocRef, {
            'monthKey': newMonthKey,
            'amount': newAmount,
            'governorateId': newGovId,
            'governorateName': newGovName,
            'notes': 'مصروف شخصي: ${title.trim()}',
            'editedByUid': actor.uid,
            'editedByName': actor.name,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      await AuditHelper.recordLog(
        firestore: _firestore,
        actor: actor,
        actionType: 'edit_personal_expense',
        descriptionAr:
            'عدّل ${actor.name} مصروفاً شخصياً ($title) إلى $newAmount للشهر $newMonthKey',
        descriptionEn:
            '${actor.name} edited personal expense ($title) to $newAmount for $newMonthKey',
        metadata: {
          'expenseId': original.id,
          'oldAmount': original.amount,
          'newAmount': newAmount,
          'oldMonthKey': oldMonthKey,
          'newMonthKey': newMonthKey,
        },
      );
      return;
    }

    // تعديل المندوب لمصروفه الخاص (كتابة عمياء للصناديق وتحديث الحقول المسموحة فقط)
    final delta = newAmount - original.amount;
    final userRef = _firestore.collection('users').doc(actor.uid);
    await _firestore.runTransaction((tx) async {
      final delegateSnap = await tx.get(userRef);

      _blindIncrementBoxesForDelegate(
        tx: tx,
        managerId: managerId,
        deductMonthKey: oldMonthKey,
        governorateId: oldGovId,
        governorateName: actor.governorateName ?? original.governorateName,
        amountDelta: delta,
      );

      if (delegateSnap.exists && delta != 0) {
        final prevBal =
            ((delegateSnap.data()!['virtualBoxBalance'] ?? 0) as num)
                .toDouble();
        tx.update(userRef, {
          'virtualBoxBalance': prevBal - delta,
        });
      }

      tx.update(expenseRef, {
        'title': title.trim(),
        'amount': newAmount,
        'notes': cleanNotes,
        'receiptImageUrl': receiptUrl,
        'editedByUid': actor.uid,
        'editedByName': actor.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: actor,
      actionType: 'edit_personal_expense',
      descriptionAr:
          'عدّل ${actor.name} مصروفه الشخصي ($title) من ${original.amount} إلى $newAmount',
      descriptionEn:
          '${actor.name} edited personal expense ($title) from ${original.amount} to $newAmount',
      metadata: {
        'expenseId': original.id,
        'oldAmount': original.amount,
        'newAmount': newAmount,
      },
    );

    await NotificationService.instance.sendCloudNotification(
      managerId: managerId,
      titleAr: 'تعديل مصروف شخصي',
      titleEn: 'Personal Expense Edited',
      bodyAr: 'عدّل ${actor.name} مصروف ($title) إلى $newAmount',
      bodyEn: '${actor.name} edited expense ($title) to $newAmount',
      type: 'personal_expense',
      targetRole: 'manager',
      audienceTags: ['MANAGER_$managerId', 'USER_${actor.uid}'],
      targetUserIds: [actor.uid],
      referenceId: original.id,
      createdByUid: actor.uid,
    );
  }

  /// حذف مصروف شخصي وإرجاع قيمته إلى الصندوق (للمدير فقط)
  Future<void> deletePersonalExpense({
    required AppUser actor,
    required PersonalExpenseModel expense,
  }) async {
    if (!actor.isManager || expense.managerId != actor.effectiveManagerId) {
      throw StateError('فقط المدير يمكنه حذف المصاريف');
    }
    final managerId = actor.effectiveManagerId;
    final deductMonth = (expense.deductedManagerMonthKey ?? '').isNotEmpty
        ? expense.deductedManagerMonthKey!
        : expense.monthKey;
    final govId =
        (expense.governorateId != null && expense.governorateId!.isNotEmpty)
            ? expense.governorateId
            : null;

    final txQuery = await _firestore
        .collection('box_transactions')
        .where('managerId', isEqualTo: managerId)
        .where('referenceId', isEqualTo: expense.id)
        .get();
    final matchingTxRefs = txQuery.docs
        .where((d) =>
            d.data()['type'] ==
            BoxTransactionType.personalExpense.firestoreValue)
        .map((d) => d.reference)
        .toList();

    final expenseRef =
        _firestore.collection('personal_expenses').doc(expense.id);
    final monthBoxRef = _firestore
        .collection('manager_monthly_boxes')
        .doc(MonthlyBox.docId(managerId, deductMonth));
    final govBoxRef = govId != null
        ? _firestore.collection('governorate_monthly_boxes').doc(
              GovernorateMonthlyBox.docId(managerId, govId, deductMonth),
            )
        : null;
    final ownerRef = (expense.userRole == 'delegate' && expense.userId.isNotEmpty)
        ? _firestore.collection('users').doc(expense.userId)
        : null;

    await _firestore.runTransaction((tx) async {
      final monthBoxSnap = await tx.get(monthBoxRef);
      final govBoxSnap = govBoxRef != null ? await tx.get(govBoxRef) : null;
      final ownerSnap = ownerRef != null ? await tx.get(ownerRef) : null;

      _applyManagerMonthBoxDelta(
        tx: tx,
        ref: monthBoxRef,
        snap: monthBoxSnap,
        managerId: managerId,
        monthKey: deductMonth,
        amountDelta: -expense.amount,
      );

      if (govBoxRef != null && govId != null) {
        _applyGovBoxDelta(
          tx: tx,
          ref: govBoxRef,
          snap: govBoxSnap,
          managerId: managerId,
          governorateId: govId,
          governorateName: expense.governorateName ?? '',
          monthKey: deductMonth,
          amountDelta: -expense.amount,
        );
      }

      if (ownerRef != null && ownerSnap != null && ownerSnap.exists) {
        final prevBal =
            ((ownerSnap.data()!['virtualBoxBalance'] ?? 0) as num).toDouble();
        tx.update(ownerRef, {
          'virtualBoxBalance': prevBal + expense.amount,
        });
      }

      for (final txDocRef in matchingTxRefs) {
        tx.delete(txDocRef);
      }
      tx.delete(expenseRef);
    });

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: actor,
      actionType: 'delete_personal_expense',
      descriptionAr:
          'حذف ${actor.name} مصروفاً شخصياً (${expense.title}) بمبلغ ${expense.amount}',
      descriptionEn:
          '${actor.name} deleted personal expense (${expense.title}): ${expense.amount}',
      metadata: {
        'expenseId': expense.id,
        'amount': expense.amount,
        'monthKey': deductMonth,
      },
    );
  }

  void _applyManagerMonthBoxDelta({
    required Transaction tx,
    required DocumentReference<Map<String, dynamic>> ref,
    required DocumentSnapshot<Map<String, dynamic>>? snap,
    required String managerId,
    required String monthKey,
    required double amountDelta,
  }) {
    if (amountDelta == 0) return;
    final parsed = ServerTimeService.parseMonthKey(monthKey);
    if (snap == null || !snap.exists) {
      if (amountDelta < 0) return;
      tx.set(ref, {
        'managerId': managerId,
        'monthKey': monthKey,
        'year': parsed.year,
        'month': parsed.month,
        'totalCompanyTopUps': 0.0,
        'totalInvoiceDeductions': 0.0,
        'totalExpenseDeductions': amountDelta,
        'currentBalance': -amountDelta,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final data = snap.data()!;
      final prevExp =
          ((data['totalExpenseDeductions'] ?? 0) as num).toDouble();
      final prevBal = ((data['currentBalance'] ?? 0) as num).toDouble();
      tx.update(ref, {
        'totalExpenseDeductions': math.max(0.0, prevExp + amountDelta),
        'currentBalance': prevBal - amountDelta,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _applyGovBoxDelta({
    required Transaction tx,
    required DocumentReference<Map<String, dynamic>> ref,
    required DocumentSnapshot<Map<String, dynamic>>? snap,
    required String managerId,
    required String governorateId,
    required String governorateName,
    required String monthKey,
    required double amountDelta,
  }) {
    if (amountDelta == 0) return;
    final parsed = ServerTimeService.parseMonthKey(monthKey);
    if (snap == null || !snap.exists) {
      if (amountDelta < 0) return;
      tx.set(ref, {
        'managerId': managerId,
        'governorateId': governorateId,
        'governorateName': governorateName,
        'monthKey': monthKey,
        'year': parsed.year,
        'month': parsed.month,
        'totalTopUps': 0.0,
        'totalInvoiceDeductions': 0.0,
        'totalExpenseDeductions': amountDelta,
        'currentBalance': -amountDelta,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final data = snap.data()!;
      final prevExp =
          ((data['totalExpenseDeductions'] ?? 0) as num).toDouble();
      final prevBal = ((data['currentBalance'] ?? 0) as num).toDouble();
      tx.update(ref, {
        'totalExpenseDeductions': math.max(0.0, prevExp + amountDelta),
        'currentBalance': prevBal - amountDelta,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _blindIncrementBoxesForDelegate({
    required Transaction tx,
    required String managerId,
    required String deductMonthKey,
    required String? governorateId,
    required String? governorateName,
    required double amountDelta,
  }) {
    if (amountDelta == 0) return;
    final parsed = ServerTimeService.parseMonthKey(deductMonthKey);
    final monthBoxRef = _firestore
        .collection('manager_monthly_boxes')
        .doc(MonthlyBox.docId(managerId, deductMonthKey));
    tx.set(
      monthBoxRef,
      {
        'managerId': managerId,
        'monthKey': deductMonthKey,
        'year': parsed.year,
        'month': parsed.month,
        'totalCompanyTopUps': FieldValue.increment(0.0),
        'totalInvoiceDeductions': FieldValue.increment(0.0),
        'totalExpenseDeductions': FieldValue.increment(amountDelta),
        'currentBalance': FieldValue.increment(-amountDelta),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (governorateId != null && governorateId.isNotEmpty) {
      final govBoxRef = _firestore.collection('governorate_monthly_boxes').doc(
            GovernorateMonthlyBox.docId(
              managerId,
              governorateId,
              deductMonthKey,
            ),
          );
      tx.set(
        govBoxRef,
        {
          'managerId': managerId,
          'governorateId': governorateId,
          'governorateName': governorateName ?? '',
          'monthKey': deductMonthKey,
          'year': parsed.year,
          'month': parsed.month,
          'totalTopUps': FieldValue.increment(0.0),
          'totalInvoiceDeductions': FieldValue.increment(0.0),
          'totalExpenseDeductions': FieldValue.increment(amountDelta),
          'currentBalance': FieldValue.increment(-amountDelta),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }
}
