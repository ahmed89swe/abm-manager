import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/services/server_time_service.dart';
import '../models/app_user.dart';
import '../models/invoice_model.dart';
import '../models/monthly_box.dart';
import '../services/audit_helper.dart';
import '../services/notification_service.dart';
import '../services/receipt_storage_service.dart';

class InvoicesRepository {
  InvoicesRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// متابعة الفواتير الحية للمدير أو المندوب (بتوافق كامل مع قواعد Firestore لضمان الظهور الفوري)
  Stream<List<InvoiceModel>> watchInvoicesForUser(AppUser user) {
    if (user.isManager) {
      return _firestore.collection('invoices').snapshots().map((snap) {
        final list = snap.docs
            .map((d) => InvoiceModel.fromMap(d.data(), d.id))
            .toList();
        list.sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
        return list;
      });
    }

    late final StreamController<List<InvoiceModel>> controller;
    final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> subs =
        [];
    final Map<int, List<InvoiceModel>> buckets = {0: [], 1: [], 2: []};

    void emitMerged() {
      if (controller.isClosed) return;
      final byId = <String, InvoiceModel>{};
      for (final list in buckets.values) {
        for (final inv in list) {
          byId[inv.id] = inv;
        }
      }
      final merged = byId.values.toList()
        ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
      controller.add(merged);
    }

    controller = StreamController<List<InvoiceModel>>(
      onListen: () {
        final govId = user.governorateId;
        if (govId != null && govId.isNotEmpty) {
          subs.add(
            _firestore
                .collection('invoices')
                .where('governorateId', isEqualTo: govId)
                .where(
                  'assignmentType',
                  isEqualTo:
                      InvoiceAssignmentType.allGovernorateDelegates.firestoreValue,
                )
                .snapshots()
                .listen(
                  (snap) {
                    buckets[0] = snap.docs
                        .map((d) => InvoiceModel.fromMap(d.data(), d.id))
                        .toList();
                    emitMerged();
                  },
                  onError: controller.addError,
                ),
          );

          subs.add(
            _firestore
                .collection('invoices')
                .where('governorateId', isEqualTo: govId)
                .where('assignedDelegateId', isEqualTo: user.uid)
                .snapshots()
                .listen(
                  (snap) {
                    buckets[1] = snap.docs
                        .map((d) => InvoiceModel.fromMap(d.data(), d.id))
                        .toList();
                    emitMerged();
                  },
                  onError: controller.addError,
                ),
          );
        }

        subs.add(
          _firestore
              .collection('invoices')
              .where('createdByUid', isEqualTo: user.uid)
              .snapshots()
              .listen(
                (snap) {
                  buckets[2] = snap.docs
                      .map((d) => InvoiceModel.fromMap(d.data(), d.id))
                      .toList();
                  emitMerged();
                },
                onError: controller.addError,
              ),
        );
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );

    return controller.stream;
  }

  List<String> _buildInvoiceAudienceTags({
    required AppUser actor,
    required String governorateId,
    required InvoiceAssignmentType assignmentType,
    String? assignedDelegateId,
    String? createdByUid,
    String? createdByRole,
  }) {
    if (actor.isDelegate) {
      return {
        'MANAGERS',
        'USER_${actor.uid}',
        if (assignedDelegateId != null && assignedDelegateId.isNotEmpty)
          'USER_$assignedDelegateId',
      }.toList();
    }

    final tags = <String>{'MANAGERS'};
    if (assignmentType == InvoiceAssignmentType.specificDelegate &&
        assignedDelegateId != null &&
        assignedDelegateId.isNotEmpty) {
      tags.add('USER_$assignedDelegateId');
    } else if (assignmentType ==
        InvoiceAssignmentType.allGovernorateDelegates) {
      tags.add('GOV_$governorateId');
    }
    if (createdByRole == 'delegate' &&
        createdByUid != null &&
        createdByUid.isNotEmpty &&
        assignmentType == InvoiceAssignmentType.manager) {
      tags.add('USER_$createdByUid');
    }
    return tags.toList();
  }

  void _applyBlindMonthlyDeduction({
    required Transaction tx,
    required String monthKey,
    required double deltaDeduction,
    required double deltaBalance,
  }) {
    final parsed = ServerTimeService.parseMonthKey(monthKey);
    final monthBoxRef =
        _firestore.collection('manager_monthly_boxes').doc(monthKey);
    tx.set(
      monthBoxRef,
      {
        'monthKey': monthKey,
        'year': parsed.year,
        'month': parsed.month,
        'totalCompanyTopUps': FieldValue.increment(0.0),
        'totalInvoiceDeductions': FieldValue.increment(deltaDeduction),
        'totalExpenseDeductions': FieldValue.increment(0.0),
        'currentBalance': FieldValue.increment(deltaBalance),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  void _applyBlindGovernorateMonthlyDeduction({
    required Transaction tx,
    required String governorateId,
    required String governorateName,
    required String monthKey,
    required double deltaDeduction,
    required double deltaBalance,
  }) {
    final parsed = ServerTimeService.parseMonthKey(monthKey);
    final govDocId = GovernorateMonthlyBox.docId(governorateId, monthKey);
    final govBoxRef =
        _firestore.collection('governorate_monthly_boxes').doc(govDocId);
    tx.set(
      govBoxRef,
      {
        'governorateId': governorateId,
        'governorateName': governorateName,
        'monthKey': monthKey,
        'year': parsed.year,
        'month': parsed.month,
        'totalTopUps': FieldValue.increment(0.0),
        'totalInvoiceDeductions': FieldValue.increment(deltaDeduction),
        'totalExpenseDeductions': FieldValue.increment(0.0),
        'currentBalance': FieldValue.increment(deltaBalance),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// إنشاء فاتورة جديدة (مع خيار التسديد الفوري أو التأجيل)
  Future<InvoiceModel> createInvoice({
    required AppUser actor,
    required String governorateId,
    required String governorateName,
    required InvoiceAssignmentType assignmentType,
    String? assignedDelegateId,
    String? assignedDelegateName,
    String? doctorId,
    String? doctorName,
    String? pharmacyId,
    String? pharmacyName,
    String? warehouseId,
    String? warehouseName,
    required List<InvoiceItem> items,
    required DateTime? managerSelectedDate,
    String? notes,
    required bool payImmediately,
    String? managerSelectedDeductMonthKey,
    PickedImageData? receiptImage,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('يجب إضافة مادة واحدة على الأقل');
    }

    // المندوب لا يختار التاريخ بل يُجلب من السيرفر دائماً
    final trustedNow = await ServerTimeService.instance.getTrustedNow();
    final effectiveDate =
        actor.isManager ? (managerSelectedDate ?? trustedNow) : trustedNow;
    final invoiceMonthKey = ServerTimeService.toMonthKey(effectiveDate);

    final totalAmount =
        items.fold<double>(0.0, (acc, item) => acc + item.totalPrice);
    final isPricePending = totalAmount <= 0;

    if (payImmediately && totalAmount <= 0) {
      throw StateError(
          'لا يمكن تسديد الفاتورة بمبلغ صفر، يرجى إدخال الأسعار أولاً.');
    }

    final invoiceRef = _firestore.collection('invoices').doc();
    final invoiceNumber =
        'INV-${effectiveDate.year}${effectiveDate.month.toString().padLeft(2, '0')}-${invoiceRef.id.substring(0, 5).toUpperCase()}';

    String? receiptUrl;
    if (payImmediately && receiptImage != null) {
      try {
        receiptUrl = await ReceiptStorageService.instance.uploadReceipt(
          image: receiptImage,
          folder: 'receipts/invoices',
          referenceId: invoiceRef.id,
        );
      } catch (_) {}
    }

    final String? deductMonthKey = payImmediately
        ? (actor.isManager
            ? (managerSelectedDeductMonthKey ?? invoiceMonthKey)
            : invoiceMonthKey)
        : null;

    final invoice = InvoiceModel(
      id: invoiceRef.id,
      invoiceNumber: invoiceNumber,
      governorateId: governorateId,
      governorateName: governorateName,
      assignmentType: assignmentType,
      assignedDelegateId: assignedDelegateId,
      assignedDelegateName: assignedDelegateName,
      doctorId: doctorId,
      doctorName: doctorName,
      pharmacyId: pharmacyId,
      pharmacyName: pharmacyName,
      warehouseId: warehouseId,
      warehouseName: warehouseName,
      items: items,
      totalAmount: totalAmount,
      isPricePending: isPricePending,
      invoiceDate: effectiveDate,
      invoiceMonthKey: invoiceMonthKey,
      notes: notes,
      status: payImmediately ? InvoiceStatus.paid : InvoiceStatus.unpaid,
      paidAt: payImmediately ? trustedNow : null,
      paidByUid: payImmediately ? actor.uid : null,
      paidByName: payImmediately ? actor.name : null,
      paidByRole: payImmediately ? actor.role.value : null,
      paidFromSource: payImmediately
          ? (actor.isManager ? 'manager_box' : 'delegate_box')
          : null,
      deductedManagerMonthKey: deductMonthKey,
      receiptImageUrl: receiptUrl,
      createdByUid: actor.uid,
      createdByName: actor.name,
      createdByRole: actor.role.value,
    );

    if (!payImmediately) {
      await invoiceRef.set(invoice.toMap(forCreate: true));
    } else {
      final monthBoxRef =
          _firestore.collection('manager_monthly_boxes').doc(deductMonthKey!);
      final govBoxRef = _firestore.collection('governorate_monthly_boxes').doc(
            GovernorateMonthlyBox.docId(governorateId, deductMonthKey),
          );
      final txRef = _firestore.collection('box_transactions').doc();
      final actorUserRef = _firestore.collection('users').doc(actor.uid);
      final parsedMonth = ServerTimeService.parseMonthKey(deductMonthKey);

      await _firestore.runTransaction((tx) async {
        // القراءات أولاً (المندوب لا يقرأ صناديق المدير إطلاقاً تفادياً لأخطاء الصلاحيات)
        DocumentSnapshot<Map<String, dynamic>>? monthBoxSnap;
        DocumentSnapshot<Map<String, dynamic>>? govBoxSnap;
        DocumentSnapshot<Map<String, dynamic>>? delegateSnap;

        if (actor.isManager) {
          monthBoxSnap = await tx.get(monthBoxRef);
          govBoxSnap = await tx.get(govBoxRef);
        } else {
          delegateSnap = await tx.get(actorUserRef);
        }

        if (actor.isManager) {
          if (monthBoxSnap == null || !monthBoxSnap.exists) {
            tx.set(monthBoxRef, {
              'monthKey': deductMonthKey,
              'year': parsedMonth.year,
              'month': parsedMonth.month,
              'totalCompanyTopUps': 0.0,
              'totalInvoiceDeductions': totalAmount,
              'totalExpenseDeductions': 0.0,
              'currentBalance': -totalAmount,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            final data = monthBoxSnap.data()!;
            final prevDed =
                ((data['totalInvoiceDeductions'] ?? 0) as num).toDouble();
            final prevBal = ((data['currentBalance'] ?? 0) as num).toDouble();
            tx.update(monthBoxRef, {
              'totalInvoiceDeductions': prevDed + totalAmount,
              'currentBalance': prevBal - totalAmount,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          if (govBoxSnap == null || !govBoxSnap.exists) {
            tx.set(govBoxRef, {
              'governorateId': governorateId,
              'governorateName': governorateName,
              'monthKey': deductMonthKey,
              'year': parsedMonth.year,
              'month': parsedMonth.month,
              'totalTopUps': 0.0,
              'totalInvoiceDeductions': totalAmount,
              'totalExpenseDeductions': 0.0,
              'currentBalance': -totalAmount,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            final gData = govBoxSnap.data()!;
            final gPrevDed =
                ((gData['totalInvoiceDeductions'] ?? 0) as num).toDouble();
            final gPrevBal =
                ((gData['currentBalance'] ?? 0) as num).toDouble();
            tx.update(govBoxRef, {
              'governorateName': governorateName,
              'totalInvoiceDeductions': gPrevDed + totalAmount,
              'currentBalance': gPrevBal - totalAmount,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        } else {
          _applyBlindMonthlyDeduction(
            tx: tx,
            monthKey: deductMonthKey,
            deltaDeduction: totalAmount,
            deltaBalance: -totalAmount,
          );
          _applyBlindGovernorateMonthlyDeduction(
            tx: tx,
            governorateId: governorateId,
            governorateName: governorateName,
            monthKey: deductMonthKey,
            deltaDeduction: totalAmount,
            deltaBalance: -totalAmount,
          );
        }

        // خصم من صندوق المندوب الافتراضي
        if (actor.isDelegate && delegateSnap != null && delegateSnap.exists) {
          final prevDelegateBal =
              ((delegateSnap.data()!['virtualBoxBalance'] ?? 0) as num)
                  .toDouble();
          tx.update(actorUserRef, {
            'virtualBoxBalance': prevDelegateBal - totalAmount,
          });
        }

        tx.set(invoiceRef, invoice.toMap(forCreate: true));
        tx.set(txRef, {
          'type': BoxTransactionType.invoicePayment.firestoreValue,
          'monthKey': deductMonthKey,
          'amount': totalAmount,
          'delegateId': actor.isDelegate ? actor.uid : assignedDelegateId,
          'delegateName': actor.isDelegate ? actor.name : assignedDelegateName,
          'governorateId': governorateId,
          'governorateName': governorateName,
          'performedByUid': actor.uid,
          'performedByName': actor.name,
          'performedByRole': actor.role.value,
          'referenceId': invoiceRef.id,
          'notes': 'تسديد فاتورة $invoiceNumber',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    }

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: actor,
      actionType: payImmediately ? 'create_and_pay_invoice' : 'create_invoice',
      descriptionAr:
          'أنشأ ${actor.name} فاتورة ($invoiceNumber) لمحافظة $governorateName بقيمة $totalAmount${payImmediately ? " وتم تسديدها فوراً" : ""}',
      descriptionEn:
          '${actor.name} created invoice $invoiceNumber for $governorateName ($totalAmount)${payImmediately ? " & paid immediately" : ""}',
      metadata: {
        'invoiceId': invoiceRef.id,
        'governorateId': governorateId,
        'totalAmount': totalAmount,
        'paidImmediately': payImmediately,
      },
    );

    final audienceTags = _buildInvoiceAudienceTags(
      actor: actor,
      governorateId: governorateId,
      assignmentType: assignmentType,
      assignedDelegateId: assignedDelegateId,
    );
    final targetIds = <String>[
      if (actor.isManager &&
          assignmentType == InvoiceAssignmentType.specificDelegate &&
          assignedDelegateId != null &&
          assignedDelegateId.isNotEmpty)
        assignedDelegateId
      else if (actor.isDelegate)
        actor.uid,
    ];

    await NotificationService.instance.sendCloudNotification(
      titleAr: payImmediately ? 'فاتورة جديدة مسددة' : 'فاتورة جديدة',
      titleEn: payImmediately ? 'New Paid Invoice' : 'New Invoice Created',
      bodyAr:
          'أنشأ ${actor.name} فاتورة $invoiceNumber ($governorateName) بمبلغ $totalAmount',
      bodyEn:
          '${actor.name} created invoice $invoiceNumber ($governorateName) amount $totalAmount',
      type: 'invoice_created',
      targetRole: actor.isManager
          ? (assignmentType == InvoiceAssignmentType.manager
              ? 'manager'
              : 'delegate')
          : 'manager',
      audienceTags: audienceTags,
      targetUserIds: targetIds,
      referenceId: invoiceRef.id,
      createdByUid: actor.uid,
    );

    return invoice;
  }

  /// تسديد فاتورة قائمة (من قبل المدير أو المندوب) مع دعم تحديث السعر المؤجل وإرفاق صورة وصل
  Future<void> payInvoice({
    required AppUser actor,
    required InvoiceModel invoice,
    required List<InvoiceItem> updatedItems,
    String? managerSelectedDeductMonthKey,
    PickedImageData? receiptImage,
  }) async {
    if (invoice.isPaid) {
      throw StateError('هذه الفاتورة مسددة بالفعل');
    }
    final newTotal =
        updatedItems.fold<double>(0.0, (acc, item) => acc + item.totalPrice);
    if (newTotal <= 0) {
      throw StateError('يرجى إدخال سعر المواد قبل إتمام التسديد');
    }

    final trustedNow = await ServerTimeService.instance.getTrustedNow();
    final deductMonthKey = actor.isManager
        ? (managerSelectedDeductMonthKey ?? invoice.invoiceMonthKey)
        : invoice.invoiceMonthKey;
    final parsedMonth = ServerTimeService.parseMonthKey(deductMonthKey);

    String? receiptUrl = invoice.receiptImageUrl;
    if (receiptImage != null) {
      try {
        receiptUrl = await ReceiptStorageService.instance.uploadReceipt(
          image: receiptImage,
          folder: 'receipts/invoices',
          referenceId: invoice.id,
        );
      } catch (_) {}
    }

    final invoiceRef = _firestore.collection('invoices').doc(invoice.id);
    final monthBoxRef =
        _firestore.collection('manager_monthly_boxes').doc(deductMonthKey);
    final govBoxRef = _firestore.collection('governorate_monthly_boxes').doc(
          GovernorateMonthlyBox.docId(invoice.governorateId, deductMonthKey),
        );
    final txRef = _firestore.collection('box_transactions').doc();
    final actorRef = _firestore.collection('users').doc(actor.uid);

    await _firestore.runTransaction((tx) async {
      // القراءات أولاً (المندوب لا يقرأ صناديق المدير إطلاقاً)
      final invSnap = await tx.get(invoiceRef);
      if (!invSnap.exists) throw StateError('الفاتورة غير موجودة');
      if (invSnap.data()!['status'] == 'paid') {
        throw StateError('تم تسديد الفاتورة مسبقاً');
      }

      DocumentSnapshot<Map<String, dynamic>>? monthBoxSnap;
      DocumentSnapshot<Map<String, dynamic>>? govBoxSnap;
      DocumentSnapshot<Map<String, dynamic>>? delegateSnap;

      if (actor.isManager) {
        monthBoxSnap = await tx.get(monthBoxRef);
        govBoxSnap = await tx.get(govBoxRef);
      } else {
        delegateSnap = await tx.get(actorRef);
      }

      if (actor.isManager) {
        if (monthBoxSnap == null || !monthBoxSnap.exists) {
          tx.set(monthBoxRef, {
            'monthKey': deductMonthKey,
            'year': parsedMonth.year,
            'month': parsedMonth.month,
            'totalCompanyTopUps': 0.0,
            'totalInvoiceDeductions': newTotal,
            'totalExpenseDeductions': 0.0,
            'currentBalance': -newTotal,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final data = monthBoxSnap.data()!;
          final prevDed =
              ((data['totalInvoiceDeductions'] ?? 0) as num).toDouble();
          final prevBal = ((data['currentBalance'] ?? 0) as num).toDouble();
          tx.update(monthBoxRef, {
            'totalInvoiceDeductions': prevDed + newTotal,
            'currentBalance': prevBal - newTotal,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        if (govBoxSnap == null || !govBoxSnap.exists) {
          tx.set(govBoxRef, {
            'governorateId': invoice.governorateId,
            'governorateName': invoice.governorateName,
            'monthKey': deductMonthKey,
            'year': parsedMonth.year,
            'month': parsedMonth.month,
            'totalTopUps': 0.0,
            'totalInvoiceDeductions': newTotal,
            'totalExpenseDeductions': 0.0,
            'currentBalance': -newTotal,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final gData = govBoxSnap.data()!;
          final gPrevDed =
              ((gData['totalInvoiceDeductions'] ?? 0) as num).toDouble();
          final gPrevBal = ((gData['currentBalance'] ?? 0) as num).toDouble();
          tx.update(govBoxRef, {
            'governorateName': invoice.governorateName,
            'totalInvoiceDeductions': gPrevDed + newTotal,
            'currentBalance': gPrevBal - newTotal,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        _applyBlindMonthlyDeduction(
          tx: tx,
          monthKey: deductMonthKey,
          deltaDeduction: newTotal,
          deltaBalance: -newTotal,
        );
        _applyBlindGovernorateMonthlyDeduction(
          tx: tx,
          governorateId: invoice.governorateId,
          governorateName: invoice.governorateName,
          monthKey: deductMonthKey,
          deltaDeduction: newTotal,
          deltaBalance: -newTotal,
        );
      }

      // خصم من صندوق المندوب الافتراضي إذا كان المندوب هو المسدد
      if (actor.isDelegate && delegateSnap != null && delegateSnap.exists) {
        final prevDelegateBal =
            ((delegateSnap.data()!['virtualBoxBalance'] ?? 0) as num)
                .toDouble();
        tx.update(actorRef, {
          'virtualBoxBalance': prevDelegateBal - newTotal,
        });
      }

      tx.update(invoiceRef, {
        'items': updatedItems.map((e) => e.toMap()).toList(),
        'totalAmount': newTotal,
        'isPricePending': false,
        'status': InvoiceStatus.paid.name,
        'paidAt': Timestamp.fromDate(trustedNow),
        'paidByUid': actor.uid,
        'paidByName': actor.name,
        'paidByRole': actor.role.value,
        'paidFromSource': actor.isManager ? 'manager_box' : 'delegate_box',
        'deductedManagerMonthKey': deductMonthKey,
        'receiptImageUrl': receiptUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(txRef, {
        'type': BoxTransactionType.invoicePayment.firestoreValue,
        'monthKey': deductMonthKey,
        'amount': newTotal,
        'delegateId': actor.isDelegate ? actor.uid : invoice.assignedDelegateId,
        'delegateName':
            actor.isDelegate ? actor.name : invoice.assignedDelegateName,
        'governorateId': invoice.governorateId,
        'governorateName': invoice.governorateName,
        'performedByUid': actor.uid,
        'performedByName': actor.name,
        'performedByRole': actor.role.value,
        'referenceId': invoice.id,
        'notes': 'تسديد فاتورة ${invoice.invoiceNumber}',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: actor,
      actionType: 'pay_invoice',
      descriptionAr:
          'سدد ${actor.name} الفاتورة ${invoice.invoiceNumber} بمبلغ $newTotal',
      descriptionEn:
          '${actor.name} paid invoice ${invoice.invoiceNumber} amount $newTotal',
      metadata: {
        'invoiceId': invoice.id,
        'amount': newTotal,
        'deductMonthKey': deductMonthKey,
      },
    );

    final audienceTags = _buildInvoiceAudienceTags(
      actor: actor,
      governorateId: invoice.governorateId,
      assignmentType: invoice.assignmentType,
      assignedDelegateId: invoice.assignedDelegateId,
      createdByUid: invoice.createdByUid,
      createdByRole: invoice.createdByRole,
    );

    await NotificationService.instance.sendCloudNotification(
      titleAr: 'تم تسديد فاتورة',
      titleEn: 'Invoice Paid',
      bodyAr:
          'سدد ${actor.name} الفاتورة ${invoice.invoiceNumber} (${invoice.governorateName}) بمبلغ $newTotal',
      bodyEn:
          '${actor.name} paid invoice ${invoice.invoiceNumber} (${invoice.governorateName}) amount $newTotal',
      type: 'invoice_paid',
      targetRole: actor.isDelegate ? 'manager' : 'delegate',
      audienceTags: audienceTags,
      targetUserIds: actor.isDelegate ? [actor.uid] : const [],
      referenceId: invoice.id,
      createdByUid: actor.uid,
    );
  }

  /// تعديل الفاتورة (للمدير فقط) مع تعديل الفروق المالية على الصناديق ذرياً
  Future<void> editInvoiceByManager({
    required AppUser manager,
    required InvoiceModel original,
    required String governorateId,
    required String governorateName,
    required InvoiceAssignmentType assignmentType,
    String? assignedDelegateId,
    String? assignedDelegateName,
    String? doctorId,
    String? doctorName,
    String? pharmacyId,
    String? pharmacyName,
    String? warehouseId,
    String? warehouseName,
    required List<InvoiceItem> items,
    required DateTime invoiceDate,
    String? notes,
    required InvoiceStatus newStatus,
    String? newDeductedMonthKey,
    PickedImageData? newReceiptImage,
  }) async {
    if (!manager.isManager) {
      throw StateError('تعديل الفواتير مسموح للمدير فقط');
    }

    final newTotal =
        items.fold<double>(0.0, (acc, item) => acc + item.totalPrice);
    final isPricePending = newTotal <= 0;
    final newInvoiceMonthKey = ServerTimeService.toMonthKey(invoiceDate);

    if (newStatus == InvoiceStatus.paid && newTotal <= 0) {
      throw StateError('لا يمكن جعل الفاتورة مسددة بمبلغ صفر');
    }

    String? receiptUrl = original.receiptImageUrl;
    if (newReceiptImage != null) {
      try {
        receiptUrl = await ReceiptStorageService.instance.uploadReceipt(
          image: newReceiptImage,
          folder: 'receipts/invoices',
          referenceId: original.id,
        );
      } catch (_) {}
    }

    final effectiveNewDeductMonth = newStatus == InvoiceStatus.paid
        ? (newDeductedMonthKey ??
            original.deductedManagerMonthKey ??
            newInvoiceMonthKey)
        : null;

    final invoiceRef = _firestore.collection('invoices').doc(original.id);

    await _firestore.runTransaction((tx) async {
      // القراءات أولاً
      final invSnap = await tx.get(invoiceRef);
      if (!invSnap.exists) throw StateError('الفاتورة غير موجودة');

      final wasPaid = original.isPaid;
      final oldAmount = original.totalAmount;
      final oldMonthKey = original.deductedManagerMonthKey;
      final oldGovId = original.governorateId;
      final oldGovName = original.governorateName;
      final wasDelegatePaid =
          wasPaid && original.paidFromSource == 'delegate_box';
      final oldDelegateUid = original.paidByUid;

      DocumentSnapshot<Map<String, dynamic>>? oldMonthSnap;
      DocumentSnapshot<Map<String, dynamic>>? newMonthSnap;
      DocumentSnapshot<Map<String, dynamic>>? oldGovSnap;
      DocumentSnapshot<Map<String, dynamic>>? newGovSnap;
      DocumentSnapshot<Map<String, dynamic>>? oldDelegateSnap;

      final oldGovDocId = (wasPaid && oldMonthKey != null)
          ? GovernorateMonthlyBox.docId(oldGovId, oldMonthKey)
          : null;
      final newGovDocId =
          (newStatus == InvoiceStatus.paid && effectiveNewDeductMonth != null)
              ? GovernorateMonthlyBox.docId(
                  governorateId,
                  effectiveNewDeductMonth,
                )
              : null;

      if (wasPaid && oldMonthKey != null) {
        oldMonthSnap = await tx.get(
          _firestore.collection('manager_monthly_boxes').doc(oldMonthKey),
        );
      }
      if (newStatus == InvoiceStatus.paid && effectiveNewDeductMonth != null) {
        if (effectiveNewDeductMonth == oldMonthKey && oldMonthSnap != null) {
          newMonthSnap = oldMonthSnap;
        } else {
          newMonthSnap = await tx.get(
            _firestore
                .collection('manager_monthly_boxes')
                .doc(effectiveNewDeductMonth),
          );
        }
      }

      if (oldGovDocId != null) {
        oldGovSnap = await tx.get(
          _firestore.collection('governorate_monthly_boxes').doc(oldGovDocId),
        );
      }
      if (newGovDocId != null) {
        if (newGovDocId == oldGovDocId && oldGovSnap != null) {
          newGovSnap = oldGovSnap;
        } else {
          newGovSnap = await tx.get(
            _firestore.collection('governorate_monthly_boxes').doc(newGovDocId),
          );
        }
      }

      if (wasDelegatePaid && oldDelegateUid != null) {
        oldDelegateSnap =
            await tx.get(_firestore.collection('users').doc(oldDelegateUid));
      }

      // 1) صافي التعديلات على الصناديق الشهرية للمدير
      final Map<String, ({double dedDelta, double balDelta})> boxChanges = {};
      if (wasPaid && oldMonthKey != null) {
        boxChanges[oldMonthKey] = (dedDelta: -oldAmount, balDelta: oldAmount);
      }
      if (newStatus == InvoiceStatus.paid && effectiveNewDeductMonth != null) {
        final existing = boxChanges[effectiveNewDeductMonth];
        boxChanges[effectiveNewDeductMonth] = (
          dedDelta: (existing?.dedDelta ?? 0) + newTotal,
          balDelta: (existing?.balDelta ?? 0) - newTotal,
        );
      }

      for (final entry in boxChanges.entries) {
        final mKey = entry.key;
        final delta = entry.value;
        if (delta.dedDelta == 0 && delta.balDelta == 0) continue;

        final boxRef =
            _firestore.collection('manager_monthly_boxes').doc(mKey);
        final snap = mKey == oldMonthKey ? oldMonthSnap : newMonthSnap;
        if (snap != null && snap.exists) {
          final data = snap.data()!;
          final curDed =
              ((data['totalInvoiceDeductions'] ?? 0) as num).toDouble();
          final curBal = ((data['currentBalance'] ?? 0) as num).toDouble();
          tx.update(boxRef, {
            'totalInvoiceDeductions': curDed + delta.dedDelta,
            'currentBalance': curBal + delta.balDelta,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final parsed = ServerTimeService.parseMonthKey(mKey);
          tx.set(boxRef, {
            'monthKey': mKey,
            'year': parsed.year,
            'month': parsed.month,
            'totalCompanyTopUps': 0.0,
            'totalInvoiceDeductions': delta.dedDelta,
            'totalExpenseDeductions': 0.0,
            'currentBalance': delta.balDelta,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // 2) صافي التعديلات على صناديق المحافظات الفرعية
      final Map<
          String,
          ({
            String govId,
            String govName,
            String mKey,
            double dedDelta,
            double balDelta
          })> govChanges = {};
      if (wasPaid && oldMonthKey != null && oldGovDocId != null) {
        govChanges[oldGovDocId] = (
          govId: oldGovId,
          govName: oldGovName,
          mKey: oldMonthKey,
          dedDelta: -oldAmount,
          balDelta: oldAmount,
        );
      }
      if (newStatus == InvoiceStatus.paid &&
          effectiveNewDeductMonth != null &&
          newGovDocId != null) {
        final existing = govChanges[newGovDocId];
        govChanges[newGovDocId] = (
          govId: governorateId,
          govName: governorateName,
          mKey: effectiveNewDeductMonth,
          dedDelta: (existing?.dedDelta ?? 0) + newTotal,
          balDelta: (existing?.balDelta ?? 0) - newTotal,
        );
      }

      for (final entry in govChanges.entries) {
        final gDocId = entry.key;
        final delta = entry.value;
        if (delta.dedDelta == 0 && delta.balDelta == 0) continue;

        final govRef =
            _firestore.collection('governorate_monthly_boxes').doc(gDocId);
        final snap = gDocId == oldGovDocId ? oldGovSnap : newGovSnap;
        if (snap != null && snap.exists) {
          final data = snap.data()!;
          final curDed =
              ((data['totalInvoiceDeductions'] ?? 0) as num).toDouble();
          final curBal = ((data['currentBalance'] ?? 0) as num).toDouble();
          tx.update(govRef, {
            'governorateName': delta.govName,
            'totalInvoiceDeductions': curDed + delta.dedDelta,
            'currentBalance': curBal + delta.balDelta,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final parsed = ServerTimeService.parseMonthKey(delta.mKey);
          tx.set(govRef, {
            'governorateId': delta.govId,
            'governorateName': delta.govName,
            'monthKey': delta.mKey,
            'year': parsed.year,
            'month': parsed.month,
            'totalTopUps': 0.0,
            'totalInvoiceDeductions': delta.dedDelta,
            'totalExpenseDeductions': 0.0,
            'currentBalance': delta.balDelta,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // 3) تعديل صندوق المندوب إن كانت مسددة سابقاً من صندوقه
      if (wasDelegatePaid &&
          oldDelegateUid != null &&
          oldDelegateSnap != null &&
          oldDelegateSnap.exists) {
        final curDelegateBal =
            ((oldDelegateSnap.data()!['virtualBoxBalance'] ?? 0) as num)
                .toDouble();
        if (newStatus == InvoiceStatus.unpaid) {
          tx.update(_firestore.collection('users').doc(oldDelegateUid), {
            'virtualBoxBalance': curDelegateBal + oldAmount,
          });
        } else if (newTotal != oldAmount) {
          tx.update(_firestore.collection('users').doc(oldDelegateUid), {
            'virtualBoxBalance': curDelegateBal + (oldAmount - newTotal),
          });
        }
      }

      tx.update(invoiceRef, {
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
        'totalAmount': newTotal,
        'isPricePending': isPricePending,
        'invoiceDate': Timestamp.fromDate(invoiceDate),
        'invoiceMonthKey': newInvoiceMonthKey,
        'notes': notes,
        'status': newStatus.name,
        'paidAt': newStatus == InvoiceStatus.paid
            ? (original.paidAt != null
                ? Timestamp.fromDate(original.paidAt!)
                : FieldValue.serverTimestamp())
            : null,
        'paidByUid': newStatus == InvoiceStatus.paid
            ? (original.paidByUid ?? manager.uid)
            : null,
        'paidByName': newStatus == InvoiceStatus.paid
            ? (original.paidByName ?? manager.name)
            : null,
        'paidByRole': newStatus == InvoiceStatus.paid
            ? (original.paidByRole ?? manager.role.value)
            : null,
        'paidFromSource': newStatus == InvoiceStatus.paid
            ? (original.paidFromSource ?? 'manager_box')
            : null,
        'deductedManagerMonthKey': effectiveNewDeductMonth,
        'receiptImageUrl': receiptUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (oldAmount != newTotal ||
          wasPaid != (newStatus == InvoiceStatus.paid) ||
          oldMonthKey != effectiveNewDeductMonth ||
          oldGovId != governorateId) {
        final txRef = _firestore.collection('box_transactions').doc();
        tx.set(txRef, {
          'type': BoxTransactionType.invoiceEditAdjustment.firestoreValue,
          'monthKey':
              effectiveNewDeductMonth ?? oldMonthKey ?? newInvoiceMonthKey,
          'amount': newTotal,
          'delegateId': assignedDelegateId,
          'delegateName': assignedDelegateName,
          'governorateId': governorateId,
          'governorateName': governorateName,
          'performedByUid': manager.uid,
          'performedByName': manager.name,
          'performedByRole': manager.role.value,
          'referenceId': original.id,
          'notes':
              'تعديل فاتورة ${original.invoiceNumber} (السابق: $oldAmount، الجديد: $newTotal)',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: manager,
      actionType: 'edit_invoice',
      descriptionAr:
          'عدّل المدير الفاتورة ${original.invoiceNumber} (المبلغ الجديد: $newTotal)',
      descriptionEn:
          'Manager edited invoice ${original.invoiceNumber} (new total: $newTotal)',
      metadata: {
        'invoiceId': original.id,
        'oldTotal': original.totalAmount,
        'newTotal': newTotal,
      },
    );

    final audienceTags = _buildInvoiceAudienceTags(
      actor: manager,
      governorateId: governorateId,
      assignmentType: assignmentType,
      assignedDelegateId: assignedDelegateId,
      createdByUid: original.createdByUid,
      createdByRole: original.createdByRole,
    );

    await NotificationService.instance.sendCloudNotification(
      titleAr: 'تعديل فاتورة',
      titleEn: 'Invoice Edited',
      bodyAr:
          'عدّل المدير الفاتورة ${original.invoiceNumber} ($governorateName)',
      bodyEn:
          'Manager updated invoice ${original.invoiceNumber} ($governorateName)',
      type: 'invoice_edited',
      targetRole: assignmentType == InvoiceAssignmentType.manager
          ? 'manager'
          : 'delegate',
      audienceTags: audienceTags,
      referenceId: original.id,
      createdByUid: manager.uid,
    );
  }
}
