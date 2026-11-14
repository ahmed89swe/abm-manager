import 'package:abm_manager/core/services/server_time_service.dart';
import 'package:abm_manager/features/version_control/version_check_gate.dart';
import 'package:abm_manager/models/app_user.dart';
import 'package:abm_manager/models/invoice_model.dart';
import 'package:abm_manager/models/monthly_box.dart';
import 'package:abm_manager/models/personal_expense_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonthlyBox, GovernorateMonthlyBox & General Box financial logic', () {
    test('General box sums monthly boxes including negative balances', () {
      const juneBox = MonthlyBox(
        monthKey: '2026-06',
        year: 2026,
        month: 6,
        totalCompanyTopUps: 1000000,
        totalInvoiceDeductions: 1200000,
        totalExpenseDeductions: 0,
        currentBalance: -200000,
      );
      const julyBox = MonthlyBox(
        monthKey: '2026-07',
        year: 2026,
        month: 7,
        totalCompanyTopUps: 2000000,
        totalInvoiceDeductions: 0,
        totalExpenseDeductions: 0,
        currentBalance: 2000000,
      );

      final generalBalance = [juneBox, julyBox]
          .fold<double>(0.0, (acc, b) => acc + b.currentBalance);
      expect(generalBalance, 1800000);
      expect(juneBox.currentBalance.isNegative, isTrue);
    });

    test('GovernorateMonthlyBox docId and balances calculate properly', () {
      expect(
        GovernorateMonthlyBox.docId('mgr_1', 'baghdad', '2026-05'),
        'mgr_1_baghdad_2026-05',
      );
      expect(
        GovernorateMonthlyBox.legacyDocId('baghdad', '2026-05'),
        'baghdad_2026-05',
      );
      expect(
        MonthlyBox.docId('mgr_1', '2026-05'),
        'mgr_1_2026-05',
      );
      final parsedBox = MonthlyBox.fromMap(
        {'year': 2026, 'month': 5, 'currentBalance': 500},
        'mgr_1_2026-05',
      );
      expect(parsedBox.monthKey, '2026-05');
      expect(parsedBox.currentBalance, 500);

      final m1 = AppUser(
        uid: 'm1',
        name: 'Manager 1',
        email: 'm1@example.com',
        phone: '',
        role: UserRole.manager,
      );
      final d1 = AppUser(
        uid: 'd1',
        managerId: 'm1',
        name: 'Delegate 1',
        email: 'd1@example.com',
        phone: '',
        role: UserRole.delegate,
      );
      expect(m1.effectiveManagerId, 'm1');
      expect(d1.effectiveManagerId, 'm1');
      const govBox = GovernorateMonthlyBox(
        id: 'baghdad_2026-05',
        governorateId: 'baghdad',
        governorateName: 'بغداد',
        monthKey: '2026-05',
        year: 2026,
        month: 5,
        totalTopUps: 500000,
        totalInvoiceDeductions: 150000,
        totalExpenseDeductions: 50000,
        currentBalance: 300000,
      );
      expect(govBox.totalDeductions, 200000);
      expect(govBox.currentBalance, 300000);
    });

    test('ServerTimeService monthKey formatting and parsing', () {
      final date = DateTime(2026, 6, 15);
      final key = ServerTimeService.toMonthKey(date);
      expect(key, '2026-06');

      final parsed = ServerTimeService.parseMonthKey(key);
      expect(parsed.year, 2026);
      expect(parsed.month, 6);
    });
  });

  group('Version comparison without build number', () {
    test('isVersionOlder compares semantic versions cleanly', () {
      expect(isVersionOlder('1.0.0', '1.0.1'), isTrue);
      expect(isVersionOlder('1.0.9', '1.1.0'), isTrue);
      expect(isVersionOlder('1.0.0+1', '2.0.0'), isTrue);
      expect(isVersionOlder('1.2.0', '1.2.0'), isFalse);
      expect(isVersionOlder('1.3.0', '1.2.9'), isFalse);
    });
  });

  group('Invoice items & optional price logic', () {
    test('Supports multi-material calculation and optional pending prices', () {
      const item1 = InvoiceItem(
        materialId: 'm1',
        materialName: 'Panadol',
        quantity: 10,
        unitPrice: 2500,
      );
      const item2 = InvoiceItem(
        materialId: 'm2',
        materialName: 'Amoxicillin',
        quantity: 5,
        unitPrice: null,
      );

      expect(item1.totalPrice, 25000);
      expect(item2.hasPrice, isFalse);
      expect(item2.totalPrice, 0);

      final items = [item1, item2];
      final total = items.fold<double>(0.0, (acc, i) => acc + i.totalPrice);
      expect(total, 25000);
    });

    test('User roles and assignment types serialize cleanly', () {
      const manager = AppUser(
        uid: 'u1',
        name: 'Manager',
        email: 'm@abm.com',
        phone: '0770',
        role: UserRole.manager,
      );
      expect(manager.isManager, isTrue);
      expect(manager.isDelegate, isFalse);

      expect(
        InvoiceAssignmentType.fromString('all_governorate_delegates'),
        InvoiceAssignmentType.allGovernorateDelegates,
      );
      expect(
        InvoiceAssignmentType.specificDelegate.firestoreValue,
        'specific_delegate',
      );
    });

    test('InvoiceModel effectiveMonthKey prioritizes deductedManagerMonthKey when paid', () {
      final paidJune = InvoiceModel(
        id: 'inv1',
        invoiceNumber: 'INV-101',
        governorateId: 'baghdad',
        governorateName: 'بغداد',
        doctorName: 'Dr. Ali',
        items: const [],
        totalAmount: 100000,
        isPricePending: false,
        status: InvoiceStatus.paid,
        assignmentType: InvoiceAssignmentType.allGovernorateDelegates,
        createdByUid: 'm1',
        createdByName: 'Manager',
        createdByRole: 'manager',
        invoiceDate: DateTime(2026, 11, 13),
        invoiceMonthKey: '2026-11',
        deductedManagerMonthKey: '2026-06',
      );
      final unpaidNov = InvoiceModel(
        id: 'inv2',
        invoiceNumber: 'INV-102',
        governorateId: 'baghdad',
        governorateName: 'بغداد',
        doctorName: 'Dr. Sara',
        items: const [],
        totalAmount: 50000,
        isPricePending: false,
        status: InvoiceStatus.unpaid,
        assignmentType: InvoiceAssignmentType.allGovernorateDelegates,
        createdByUid: 'm1',
        createdByName: 'Manager',
        createdByRole: 'manager',
        invoiceDate: DateTime(2026, 11, 13),
        invoiceMonthKey: '2026-11',
      );
      expect(paidJune.effectiveMonthKey, '2026-06');
      expect(unpaidNov.effectiveMonthKey, '2026-11');
    });

    test('PersonalExpenseModel serializes governorateName and edited state cleanly', () {
      final original = PersonalExpenseModel(
        id: 'exp1',
        managerId: 'm1',
        userId: 'm1',
        userName: 'Manager',
        userRole: 'manager',
        governorateId: 'baghdad',
        governorateName: 'بغداد',
        amount: 115000,
        title: 'نقل',
        notes: 'شحن',
        expenseDate: DateTime(2026, 6, 10),
        monthKey: '2026-06',
        deductedManagerMonthKey: '2026-06',
      );
      expect(original.isEdited, isFalse);
      final map = original.toMap();
      expect(map['governorateName'], 'بغداد');
      expect(map['deductedManagerMonthKey'], '2026-06');

      final parsedEdited = PersonalExpenseModel.fromMap({
        'managerId': 'm1',
        'userId': 'm1',
        'userName': 'Manager',
        'userRole': 'manager',
        'governorateId': 'baghdad',
        'governorateName': 'بغداد',
        'amount': 115000,
        'title': 'نقل',
        'monthKey': '2026-06',
        'editedByUid': 'm1',
        'editedByName': 'Manager',
      }, 'exp1');
      expect(parsedEdited.isEdited, isTrue);
      expect(parsedEdited.governorateName, 'بغداد');
    });

    test('GovernorateMonthlyBox builds composite docId and calculates deductions', () {
      expect(
        GovernorateMonthlyBox.docId('m1', 'gov_baghdad', '2026-11'),
        'm1_gov_baghdad_2026-11',
      );
      expect(
        GovernorateMonthlyBox.legacyDocId('gov_baghdad', '2026-11'),
        'gov_baghdad_2026-11',
      );

      final emptyGovBox = GovernorateMonthlyBox.empty(
        managerId: 'm1',
        governorateId: 'gov_baghdad',
        governorateName: 'بغداد',
        monthKey: '2026-06',
      );
      expect(emptyGovBox.id, 'm1_gov_baghdad_2026-06');
      expect(emptyGovBox.year, 2026);
      expect(emptyGovBox.month, 6);
      expect(emptyGovBox.totalDeductions, 0);

      final parsedGovBox = GovernorateMonthlyBox.fromMap({
        'managerId': 'm1',
        'governorateId': 'gov_baghdad',
        'governorateName': 'بغداد',
        'monthKey': '2026-11',
        'year': 2026,
        'month': 11,
        'totalTopUps': 1000000,
        'totalInvoiceDeductions': 250000,
        'totalExpenseDeductions': 100000,
        'currentBalance': 650000,
      }, 'm1_gov_baghdad_2026-11');
      expect(parsedGovBox.totalDeductions, 350000);
      expect(parsedGovBox.currentBalance, 650000);
    });

    test('MonthlyBox resolves monthKey fallback from scoped docId cleanly', () {
      expect(MonthlyBox.docId('m1', '2026-11'), 'm1_2026-11');
      final parsed = MonthlyBox.fromMap({
        'managerId': 'm1',
        'year': 2026,
        'month': 11,
        'totalCompanyTopUps': 500000,
        'totalInvoiceDeductions': 125000,
        'totalExpenseDeductions': 25000,
        'currentBalance': 350000,
      }, 'm1_2026-11');
      expect(parsed.monthKey, '2026-11');
      expect(parsed.totalDeductions, 150000);
    });

    test('InvoiceModel matchesSearchQuery matches doctor, pharmacy, warehouse, and material names', () {
      final invoice = InvoiceModel(
        id: 'inv_search',
        managerId: 'm1',
        invoiceNumber: 'INV-202607-AB12C',
        governorateId: 'baghdad',
        governorateName: 'بغداد',
        doctorName: 'د. أحمد كريم',
        pharmacyName: 'صيدلية الشفاء المركزي',
        warehouseName: 'مذخر الرافدين',
        items: const [
          InvoiceItem(
            materialId: 'mat1',
            materialName: 'بانادول اكسترا 500',
            quantity: 2,
            unitPrice: 5000,
          ),
          InvoiceItem(
            materialId: 'mat2',
            materialName: 'أوجمنتين 1جم',
            quantity: 1,
            unitPrice: 15000,
          ),
        ],
        totalAmount: 25000,
        isPricePending: false,
        status: InvoiceStatus.unpaid,
        assignmentType: InvoiceAssignmentType.specificDelegate,
        assignedDelegateId: 'd1',
        assignedDelegateName: 'يوسف اسماعيل',
        createdByUid: 'm1',
        createdByName: 'Manager',
        createdByRole: 'manager',
        invoiceDate: DateTime(2026, 7, 14),
        invoiceMonthKey: '2026-07',
      );

      expect(invoice.invoiceDateMonthKey, '2026-07');
      expect(invoice.matchesSearchQuery(''), isTrue);
      expect(invoice.matchesSearchQuery('احمد'), isTrue); // Arabic alef normalization
      expect(invoice.matchesSearchQuery('أحمد كريم'), isTrue);
      expect(invoice.matchesSearchQuery('الشفاء'), isTrue);
      expect(invoice.matchesSearchQuery('بانادول'), isTrue);
      expect(invoice.matchesSearchQuery('اوجمنتين'), isTrue);
      expect(invoice.matchesSearchQuery('الرافدين'), isTrue);
      expect(invoice.matchesSearchQuery('احمد بانادول'), isTrue);
      expect(invoice.matchesSearchQuery('AB12C'), isTrue);
      expect(invoice.matchesSearchQuery('أموكسيسيلين'), isFalse);
    });

    test('BoxTransaction supports delegateVirtualWithdraw, delegateVirtualAdjustment & signedDelta', () {
      expect(
        BoxTransactionType.delegateVirtualWithdraw.firestoreValue,
        'delegate_virtual_withdraw',
      );
      expect(
        BoxTransactionType.delegateVirtualAdjustment.firestoreValue,
        'delegate_virtual_adjustment',
      );
      expect(
        BoxTransactionType.fromString('delegate_virtual_withdraw'),
        BoxTransactionType.delegateVirtualWithdraw,
      );
      expect(
        BoxTransactionType.fromString('delegate_virtual_adjustment'),
        BoxTransactionType.delegateVirtualAdjustment,
      );

      final withdrawTx = BoxTransaction.fromMap({
        'managerId': 'm1',
        'type': 'delegate_virtual_withdraw',
        'monthKey': '2026-11',
        'amount': 75000,
        'signedDelta': -75000,
        'delegateId': 'd1',
        'delegateName': 'يوسف',
        'performedByUid': 'm1',
        'performedByName': 'Ameer',
        'performedByRole': 'manager',
      }, 'tx_w1');

      expect(withdrawTx.isDelegateVirtualTx, isTrue);
      expect(withdrawTx.effectiveSignedDelta, -75000);
      expect(withdrawTx.toMap()['signedDelta'], -75000);

      final adjustDownTx = BoxTransaction.fromMap({
        'managerId': 'm1',
        'type': 'delegate_virtual_adjustment',
        'monthKey': '2026-11',
        'amount': 120000,
        'signedDelta': -120000,
        'delegateId': 'd1',
        'performedByUid': 'm1',
        'performedByName': 'Ameer',
        'performedByRole': 'manager',
      }, 'tx_a1');
      expect(adjustDownTx.isDelegateVirtualTx, isTrue);
      expect(adjustDownTx.effectiveSignedDelta, -120000);

      final adjustUpTx = BoxTransaction.fromMap({
        'managerId': 'm1',
        'type': 'delegate_virtual_adjustment',
        'monthKey': '2026-11',
        'amount': 40000,
        'signedDelta': 40000,
        'delegateId': 'd1',
        'performedByUid': 'm1',
        'performedByName': 'Ameer',
        'performedByRole': 'manager',
      }, 'tx_a2');
      expect(adjustUpTx.effectiveSignedDelta, 40000);
    });
  });
}
