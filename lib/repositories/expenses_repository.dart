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
    Query<Map<String, dynamic>> query =
        _firestore.collection('personal_expenses');
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
    final parsed = ServerTimeService.parseMonthKey(deductMonthKey);

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

    final monthBoxRef =
        _firestore.collection('manager_monthly_boxes').doc(deductMonthKey);
    final hasGov =
        actor.governorateId != null && actor.governorateId!.isNotEmpty;
    final govBoxRef = hasGov
        ? _firestore.collection('governorate_monthly_boxes').doc(
              GovernorateMonthlyBox.docId(actor.governorateId!, deductMonthKey),
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
        if (monthBoxSnap == null || !monthBoxSnap.exists) {
          tx.set(monthBoxRef, {
            'monthKey': deductMonthKey,
            'year': parsed.year,
            'month': parsed.month,
            'totalCompanyTopUps': 0.0,
            'totalInvoiceDeductions': 0.0,
            'totalExpenseDeductions': amount,
            'currentBalance': -amount,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final data = monthBoxSnap.data()!;
          final prevExp =
              ((data['totalExpenseDeductions'] ?? 0) as num).toDouble();
          final prevBal = ((data['currentBalance'] ?? 0) as num).toDouble();
          tx.update(monthBoxRef, {
            'totalExpenseDeductions': prevExp + amount,
            'currentBalance': prevBal - amount,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        if (govBoxRef != null && hasGov) {
          if (govBoxSnap == null || !govBoxSnap.exists) {
            tx.set(govBoxRef, {
              'governorateId': actor.governorateId,
              'governorateName': actor.governorateName ?? '',
              'monthKey': deductMonthKey,
              'year': parsed.year,
              'month': parsed.month,
              'totalTopUps': 0.0,
              'totalInvoiceDeductions': 0.0,
              'totalExpenseDeductions': amount,
              'currentBalance': -amount,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            final gData = govBoxSnap.data()!;
            final gPrevExp =
                ((gData['totalExpenseDeductions'] ?? 0) as num).toDouble();
            final gPrevBal =
                ((gData['currentBalance'] ?? 0) as num).toDouble();
            tx.update(govBoxRef, {
              'totalExpenseDeductions': gPrevExp + amount,
              'currentBalance': gPrevBal - amount,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } else {
        // المندوب يكتب بشكل أعمى عبر FieldValue.increment دون قراءة صناديق المدير
        tx.set(
          monthBoxRef,
          {
            'monthKey': deductMonthKey,
            'year': parsed.year,
            'month': parsed.month,
            'totalCompanyTopUps': FieldValue.increment(0.0),
            'totalInvoiceDeductions': FieldValue.increment(0.0),
            'totalExpenseDeductions': FieldValue.increment(amount),
            'currentBalance': FieldValue.increment(-amount),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (govBoxRef != null && hasGov) {
          tx.set(
            govBoxRef,
            {
              'governorateId': actor.governorateId,
              'governorateName': actor.governorateName ?? '',
              'monthKey': deductMonthKey,
              'year': parsed.year,
              'month': parsed.month,
              'totalTopUps': FieldValue.increment(0.0),
              'totalInvoiceDeductions': FieldValue.increment(0.0),
              'totalExpenseDeductions': FieldValue.increment(amount),
              'currentBalance': FieldValue.increment(-amount),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }

      if (actor.isDelegate && delegateSnap != null && delegateSnap.exists) {
        final prevBal =
            ((delegateSnap.data()!['virtualBoxBalance'] ?? 0) as num)
                .toDouble();
        tx.update(userRef, {
          'virtualBoxBalance': prevBal - amount,
        });
      }

      final expense = PersonalExpenseModel(
        id: expenseRef.id,
        userId: actor.uid,
        userName: actor.name,
        userRole: actor.role.value,
        governorateId: actor.governorateId,
        amount: amount,
        title: title.trim(),
        notes: notes?.trim(),
        receiptImageUrl: receiptUrl,
        expenseDate: effectiveDate,
        monthKey: monthKey,
        deductedManagerMonthKey: deductMonthKey,
      );

      tx.set(expenseRef, expense.toMap());
      tx.set(txRef, {
        'type': BoxTransactionType.personalExpense.firestoreValue,
        'monthKey': deductMonthKey,
        'amount': amount,
        'delegateId': actor.isDelegate ? actor.uid : null,
        'delegateName': actor.isDelegate ? actor.name : null,
        'governorateId': actor.governorateId,
        'governorateName': actor.governorateName,
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
      },
    );

    await NotificationService.instance.sendCloudNotification(
      titleAr: 'مصروف شخصي جديد',
      titleEn: 'New Personal Expense',
      bodyAr: 'سجل ${actor.name} مصروفاً ($title) بمبلغ $amount',
      bodyEn: '${actor.name} added personal expense ($title): $amount',
      type: 'personal_expense',
      targetRole: 'manager',
      audienceTags: actor.isDelegate
          ? ['MANAGERS', 'USER_${actor.uid}']
          : const ['MANAGERS'],
      targetUserIds: actor.isDelegate ? [actor.uid] : const [],
      referenceId: expenseRef.id,
      createdByUid: actor.uid,
    );
  }
}
