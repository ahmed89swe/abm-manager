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

  /// تعبئة صندوق شهري من الشركة (مع ربط اختياري/أساسي بالمحافظة والشهر لدعم الصناديق الفرعية)
  Future<void> topUpMonthlyBoxFromCompany({
    required AppUser manager,
    required String monthKey,
    required double amount,
    String? governorateId,
    String? governorateName,
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
    final hasGov = governorateId != null && governorateId.isNotEmpty;
    final cleanGovName =
        hasGov ? ((governorateName ?? '').trim()) : null;
    final govBoxRef = hasGov
        ? _firestore.collection('governorate_monthly_boxes').doc(
              GovernorateMonthlyBox.docId(managerId, governorateId, monthKey),
            )
        : null;
    final txRef = _firestore.collection('box_transactions').doc();

    await _firestore.runTransaction((tx) async {
      // القراءات أولاً
      final boxSnap = await tx.get(boxRef);
      final govBoxSnap = govBoxRef != null ? await tx.get(govBoxRef) : null;

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

      if (govBoxRef != null && govBoxSnap != null) {
        if (!govBoxSnap.exists) {
          tx.set(govBoxRef, {
            'managerId': managerId,
            'governorateId': governorateId,
            'governorateName': cleanGovName ?? '',
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
          final gData = govBoxSnap.data()!;
          final prevTopUp = ((gData['totalTopUps'] ?? 0) as num).toDouble();
          final prevBalance =
              ((gData['currentBalance'] ?? 0) as num).toDouble();
          tx.update(govBoxRef, {
            if (cleanGovName != null && cleanGovName.isNotEmpty)
              'governorateName': cleanGovName,
            'totalTopUps': prevTopUp + amount,
            'currentBalance': prevBalance + amount,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      tx.set(txRef, {
        'managerId': managerId,
        'type': BoxTransactionType.companyTopUp.firestoreValue,
        'monthKey': monthKey,
        'amount': amount,
        'governorateId': hasGov ? governorateId : null,
        'governorateName':
            hasGov && cleanGovName != null && cleanGovName.isNotEmpty
                ? cleanGovName
                : null,
        'performedByUid': manager.uid,
        'performedByName': manager.name,
        'performedByRole': manager.role.value,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    final govDescAr = (hasGov && cleanGovName != null && cleanGovName.isNotEmpty)
        ? ' - محافظة $cleanGovName'
        : '';
    final govDescEn = (hasGov && cleanGovName != null && cleanGovName.isNotEmpty)
        ? ' ($cleanGovName)'
        : '';

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: manager,
      actionType: 'company_topup',
      descriptionAr:
          'تعبئة صندوق شهر $monthKey$govDescAr من الشركة بمبلغ $amount',
      descriptionEn:
          'Company top-up for Month $monthKey$govDescEn: $amount',
      metadata: {
        'monthKey': monthKey,
        if (hasGov) 'governorateId': governorateId,
        if (cleanGovName != null && cleanGovName.isNotEmpty)
          'governorateName': cleanGovName,
        'amount': amount,
        'notes': notes,
      },
    );

    await NotificationService.instance.sendCloudNotification(
      managerId: managerId,
      titleAr: 'تعبئة صندوق شهري',
      titleEn: 'Monthly Box Topped Up',
      bodyAr: 'تمت تعبئة صندوق شهر $monthKey$govDescAr بمبلغ $amount',
      bodyEn: 'Month $monthKey$govDescEn box topped up with $amount',
      type: 'company_topup',
      targetRole: 'manager',
      audienceTags: ['MANAGER_$managerId'],
      referenceId: monthKey,
      createdByUid: manager.uid,
    );
  }

  /// تعديل عملية تعبئة من الشركة (تعديل المبلغ و/أو الشهر و/أو المحافظة و/أو الملاحظات)
  Future<void> editCompanyTopUp({
    required AppUser manager,
    required BoxTransaction oldTx,
    required String newMonthKey,
    required double newAmount,
    String? newGovernorateId,
    String? newGovernorateName,
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
    String? actualOldGovId = oldTx.governorateId;

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
      actualOldGovId = txData['governorateId'] as String?;
      final actualOldGovName = txData['governorateName'] as String?;

      final String? cleanNewGovId =
          (newGovernorateId != null && newGovernorateId.isNotEmpty)
              ? newGovernorateId
              : null;
      final String? cleanNewGovName = (cleanNewGovId != null &&
              newGovernorateName != null &&
              newGovernorateName.trim().isNotEmpty)
          ? newGovernorateName.trim()
          : null;

      // تجميع صافي الفروق لكل صندوق شهر عام وكل صندوق محافظة
      final Map<String, double> monthDeltas = {};
      if (actualOldMonthKey.isNotEmpty) {
        monthDeltas[actualOldMonthKey] =
            (monthDeltas[actualOldMonthKey] ?? 0.0) - actualOldAmount;
      }
      monthDeltas[newMonthKey] =
          (monthDeltas[newMonthKey] ?? 0.0) + newAmount;

      final Map<String, ({String govId, String govName, String monthKey, double delta})>
          govDeltas = {};
      if (actualOldGovId != null &&
          actualOldGovId!.isNotEmpty &&
          actualOldMonthKey.isNotEmpty) {
        final oldGDocId = GovernorateMonthlyBox.docId(
          managerId,
          actualOldGovId!,
          actualOldMonthKey,
        );
        govDeltas[oldGDocId] = (
          govId: actualOldGovId!,
          govName: actualOldGovName ?? '',
          monthKey: actualOldMonthKey,
          delta: -actualOldAmount,
        );
      }
      if (cleanNewGovId != null) {
        final newGDocId = GovernorateMonthlyBox.docId(
          managerId,
          cleanNewGovId,
          newMonthKey,
        );
        final prev = govDeltas[newGDocId];
        govDeltas[newGDocId] = (
          govId: cleanNewGovId,
          govName: cleanNewGovName ?? prev?.govName ?? '',
          monthKey: newMonthKey,
          delta: (prev?.delta ?? 0.0) + newAmount,
        );
      }

      // 1) جميع القراءات أولاً
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> monthSnaps = {};
      for (final entry in monthDeltas.entries) {
        if (entry.value == 0) continue;
        final ref = _firestore
            .collection('manager_monthly_boxes')
            .doc(MonthlyBox.docId(managerId, entry.key));
        monthSnaps[entry.key] = await tx.get(ref);
      }

      final Map<String, DocumentSnapshot<Map<String, dynamic>>> govSnaps = {};
      for (final entry in govDeltas.entries) {
        if (entry.value.delta == 0) continue;
        final ref = _firestore
            .collection('governorate_monthly_boxes')
            .doc(entry.key);
        govSnaps[entry.key] = await tx.get(ref);
      }

      // 2) الكتابة بعد انتهاء القراءات
      for (final entry in monthDeltas.entries) {
        final delta = entry.value;
        if (delta == 0) continue;
        final mKey = entry.key;
        final ref = _firestore
            .collection('manager_monthly_boxes')
            .doc(MonthlyBox.docId(managerId, mKey));
        final snap = monthSnaps[mKey]!;
        if (!snap.exists) {
          final parsed = ServerTimeService.parseMonthKey(mKey);
          tx.set(ref, {
            'managerId': managerId,
            'monthKey': mKey,
            'year': parsed.year,
            'month': parsed.month,
            'totalCompanyTopUps': delta < 0 ? 0.0 : delta,
            'totalInvoiceDeductions': 0.0,
            'totalExpenseDeductions': 0.0,
            'currentBalance': delta,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final data = snap.data()!;
          final prevTopUp =
              ((data['totalCompanyTopUps'] ?? 0) as num).toDouble();
          final prevBal = ((data['currentBalance'] ?? 0) as num).toDouble();
          final nextTopUp =
              (prevTopUp + delta) < 0 ? 0.0 : (prevTopUp + delta);
          tx.update(ref, {
            'totalCompanyTopUps': nextTopUp,
            'currentBalance': prevBal + delta,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      for (final entry in govDeltas.entries) {
        final info = entry.value;
        if (info.delta == 0) continue;
        final ref =
            _firestore.collection('governorate_monthly_boxes').doc(entry.key);
        final snap = govSnaps[entry.key]!;
        if (!snap.exists) {
          final parsed = ServerTimeService.parseMonthKey(info.monthKey);
          tx.set(ref, {
            'managerId': managerId,
            'governorateId': info.govId,
            'governorateName': info.govName,
            'monthKey': info.monthKey,
            'year': parsed.year,
            'month': parsed.month,
            'totalTopUps': info.delta < 0 ? 0.0 : info.delta,
            'totalInvoiceDeductions': 0.0,
            'totalExpenseDeductions': 0.0,
            'currentBalance': info.delta,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final gData = snap.data()!;
          final prevTopUp = ((gData['totalTopUps'] ?? 0) as num).toDouble();
          final prevBal = ((gData['currentBalance'] ?? 0) as num).toDouble();
          final nextTopUp =
              (prevTopUp + info.delta) < 0 ? 0.0 : (prevTopUp + info.delta);
          tx.update(ref, {
            if (info.govName.isNotEmpty) 'governorateName': info.govName,
            'totalTopUps': nextTopUp,
            'currentBalance': prevBal + info.delta,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      tx.update(txRef, {
        'monthKey': newMonthKey,
        'governorateId': cleanNewGovId,
        'governorateName': cleanNewGovName,
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
        'oldGovernorateId': actualOldGovId,
        'newGovernorateId': newGovernorateId,
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

  /// حذف عملية تعبئة (من الشركة / لمحافظة / لمندوب) وعكس أثرها المالي بدقة ذرية
  Future<void> deleteTopUpTransaction({
    required AppUser manager,
    required BoxTransaction txDoc,
  }) async {
    if (!manager.isManager) {
      throw StateError('حذف عمليات التعبئة متاح للمدير فقط');
    }
    final managerId = manager.effectiveManagerId;
    final txRef = _firestore.collection('box_transactions').doc(txDoc.id);

    double deletedAmount = txDoc.amount;
    String deletedMonthKey = txDoc.monthKey;
    String? deletedGovName = txDoc.governorateName;
    String? deletedDelegateName = txDoc.delegateName;
    BoxTransactionType deletedType = txDoc.type;

    await _firestore.runTransaction((tx) async {
      // 1) جميع القراءات أولاً
      final txSnap = await tx.get(txRef);
      if (!txSnap.exists || txSnap.data() == null) {
        throw StateError('عملية التعبئة غير موجودة أو تم حذفها مسبقاً');
      }
      final data = txSnap.data()!;
      deletedType = BoxTransactionType.fromString(data['type'] as String?);
      if (deletedType != BoxTransactionType.companyTopUp &&
          deletedType != BoxTransactionType.governorateTopUp &&
          deletedType != BoxTransactionType.delegateVirtualTopUp) {
        throw StateError('هذه الحركة ليست عملية تعبئة قابلة للحذف من هنا');
      }

      deletedAmount = ((data['amount'] ?? txDoc.amount) as num).toDouble();
      deletedMonthKey = (data['monthKey'] as String?) ?? txDoc.monthKey;
      final govId = (data['governorateId'] as String?) ?? '';
      deletedGovName = data['governorateName'] as String?;
      final delegateId = (data['delegateId'] as String?) ?? '';
      deletedDelegateName = data['delegateName'] as String?;

      DocumentReference<Map<String, dynamic>>? monthBoxRef;
      DocumentSnapshot<Map<String, dynamic>>? monthBoxSnap;
      DocumentReference<Map<String, dynamic>>? govBoxRef;
      DocumentSnapshot<Map<String, dynamic>>? govBoxSnap;
      DocumentReference<Map<String, dynamic>>? delegateRef;
      DocumentSnapshot<Map<String, dynamic>>? delegateSnap;

      if (deletedType == BoxTransactionType.companyTopUp &&
          deletedMonthKey.isNotEmpty) {
        monthBoxRef = _firestore
            .collection('manager_monthly_boxes')
            .doc(MonthlyBox.docId(managerId, deletedMonthKey));
        monthBoxSnap = await tx.get(monthBoxRef);
      }

      if ((deletedType == BoxTransactionType.companyTopUp ||
              deletedType == BoxTransactionType.governorateTopUp) &&
          govId.isNotEmpty &&
          deletedMonthKey.isNotEmpty) {
        govBoxRef = _firestore.collection('governorate_monthly_boxes').doc(
              GovernorateMonthlyBox.docId(managerId, govId, deletedMonthKey),
            );
        govBoxSnap = await tx.get(govBoxRef);
      }

      if (deletedType == BoxTransactionType.delegateVirtualTopUp &&
          delegateId.isNotEmpty) {
        delegateRef = _firestore.collection('users').doc(delegateId);
        delegateSnap = await tx.get(delegateRef);
      }

      // 2) الكتابة بعد انتهاء القراءات
      if (monthBoxRef != null &&
          monthBoxSnap != null &&
          monthBoxSnap.exists &&
          monthBoxSnap.data() != null) {
        final mData = monthBoxSnap.data()!;
        final prevTopUp =
            ((mData['totalCompanyTopUps'] ?? 0) as num).toDouble();
        final prevBal = ((mData['currentBalance'] ?? 0) as num).toDouble();
        final nextTopUp =
            (prevTopUp - deletedAmount) < 0 ? 0.0 : (prevTopUp - deletedAmount);
        tx.update(monthBoxRef, {
          'totalCompanyTopUps': nextTopUp,
          'currentBalance': prevBal - deletedAmount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (govBoxRef != null &&
          govBoxSnap != null &&
          govBoxSnap.exists &&
          govBoxSnap.data() != null) {
        final gData = govBoxSnap.data()!;
        final prevTopUp = ((gData['totalTopUps'] ?? 0) as num).toDouble();
        final prevBal = ((gData['currentBalance'] ?? 0) as num).toDouble();
        final nextTopUp =
            (prevTopUp - deletedAmount) < 0 ? 0.0 : (prevTopUp - deletedAmount);
        tx.update(govBoxRef, {
          'totalTopUps': nextTopUp,
          'currentBalance': prevBal - deletedAmount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (delegateRef != null &&
          delegateSnap != null &&
          delegateSnap.exists &&
          delegateSnap.data() != null) {
        final prevVirtual =
            ((delegateSnap.data()!['virtualBoxBalance'] ?? 0) as num)
                .toDouble();
        tx.update(delegateRef, {
          'virtualBoxBalance': prevVirtual - deletedAmount,
        });
      }

      tx.delete(txRef);
    });

    final targetLabel = (deletedGovName != null && deletedGovName!.isNotEmpty)
        ? ' ($deletedGovName)'
        : (deletedDelegateName != null && deletedDelegateName!.isNotEmpty
            ? ' ($deletedDelegateName)'
            : '');

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: manager,
      actionType: 'delete_topup',
      descriptionAr:
          'حذف المدير عملية التعبئة$targetLabel لشهر $deletedMonthKey بمبلغ $deletedAmount وعكس أثرها المالي',
      descriptionEn:
          'Manager deleted top-up$targetLabel ($deletedMonthKey: $deletedAmount) and reversed box balances',
      metadata: {
        'transactionId': txDoc.id,
        'type': deletedType.firestoreValue,
        'monthKey': deletedMonthKey,
        'amount': deletedAmount,
        'governorateName': deletedGovName,
        'delegateName': deletedDelegateName,
      },
    );
  }
}
