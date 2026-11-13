import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/server_time_service.dart';
import '../models/app_user.dart';
import '../models/audit_log_model.dart';
import '../models/invoice_model.dart';
import '../models/master_data_models.dart';
import '../models/monthly_box.dart';
import '../models/personal_expense_model.dart';
import '../repositories/auth_repository.dart';
import '../repositories/boxes_repository.dart';
import '../repositories/expenses_repository.dart';
import '../repositories/invoices_repository.dart';
import '../repositories/logs_notifications_repository.dart';
import '../repositories/master_data_repository.dart';
import '../repositories/version_repository.dart';

// المستودعات
final authRepositoryProvider = Provider((ref) => AuthRepository());
final boxesRepositoryProvider = Provider((ref) => BoxesRepository());
final masterDataRepositoryProvider = Provider((ref) => MasterDataRepository());
final invoicesRepositoryProvider = Provider((ref) => InvoicesRepository());
final expensesRepositoryProvider = Provider((ref) => ExpensesRepository());
final versionRepositoryProvider = Provider((ref) => VersionRepository());
final logsNotificationsRepositoryProvider =
    Provider((ref) => LogsNotificationsRepository());

// حالة المصادقة والمستخدم الحالي
final firebaseAuthStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProfileProvider = StreamProvider<AppUser?>((ref) {
  final authAsync = ref.watch(firebaseAuthStateProvider);
  final user = authAsync.value;
  if (user == null) {
    return Stream.value(null);
  }
  return ref.watch(authRepositoryProvider).watchUserProfile(user.uid);
});

/// مفتاح هوية مستقر يمنع إعادة تشغيل البث عند تغيّر الرصيد أو الاسم أو الصورة الشخصية
final _userIdentityProvider = Provider<
    ({String? uid, UserRole? role, String? govId, String? managerId})>((ref) {
  return ref.watch(
    currentUserProfileProvider.select(
      (s) => (
        uid: s.value?.uid,
        role: s.value?.role,
        govId: s.value?.governorateId,
        managerId: s.value?.effectiveManagerId,
      ),
    ),
  );
});

// الوقت الموثوق من السيرفر والشهر الحالي
final trustedNowProvider = FutureProvider<DateTime>((ref) {
  return ServerTimeService.instance.getTrustedNow();
});

final currentMonthKeyProvider = FutureProvider<String>((ref) async {
  final now = await ref.watch(trustedNowProvider.future);
  return ServerTimeService.toMonthKey(now);
});

// إعدادات الإصدار والتحديثات
final versionConfigProvider = StreamProvider<AppVersionConfig?>((ref) {
  return ref.watch(versionRepositoryProvider).watchVersionConfig();
});

// الثوابت (المحافظات والمواد فقط - معزولة لكل مدير)
final governoratesProvider = StreamProvider<List<Governorate>>((ref) {
  final managerId = ref.watch(_userIdentityProvider).managerId ?? '';
  if (managerId.isEmpty) return Stream.value(const []);
  return ref
      .watch(masterDataRepositoryProvider)
      .watchGovernorates(managerId);
});

final materialsProvider = StreamProvider<List<MaterialEntity>>((ref) {
  final managerId = ref.watch(_userIdentityProvider).managerId ?? '';
  if (managerId.isEmpty) return Stream.value(const []);
  return ref.watch(masterDataRepositoryProvider).watchMaterials(managerId);
});

// المندوبون (للمدير)
final delegatesProvider = StreamProvider<List<AppUser>>((ref) {
  final identity = ref.watch(_userIdentityProvider);
  final managerId = identity.managerId ?? '';
  if (identity.uid == null ||
      identity.role != UserRole.manager ||
      managerId.isEmpty) {
    return Stream.value(const []);
  }
  return ref.watch(authRepositoryProvider).watchAllDelegates(managerId);
});

// الصناديق الشهرية للمدير (محمية - للمدير فقط)
final monthlyBoxesProvider = StreamProvider<List<MonthlyBox>>((ref) {
  final identity = ref.watch(_userIdentityProvider);
  final managerId = identity.managerId ?? '';
  if (identity.uid == null ||
      identity.role != UserRole.manager ||
      managerId.isEmpty) {
    return Stream.value(const []);
  }
  return ref.watch(boxesRepositoryProvider).watchMonthlyBoxes(managerId);
});

// الصناديق الشهرية الفرعية للمحافظات (للمدير فقط)
final governorateMonthlyBoxesProvider =
    StreamProvider<List<GovernorateMonthlyBox>>((ref) {
  final identity = ref.watch(_userIdentityProvider);
  final managerId = identity.managerId ?? '';
  if (identity.uid == null ||
      identity.role != UserRole.manager ||
      managerId.isEmpty) {
    return Stream.value(const []);
  }
  return ref
      .watch(boxesRepositoryProvider)
      .watchGovernorateMonthlyBoxes(managerId);
});

final allBoxTransactionsProvider = StreamProvider<List<BoxTransaction>>((ref) {
  final identity = ref.watch(_userIdentityProvider);
  final managerId = identity.managerId ?? '';
  if (identity.uid == null ||
      identity.role != UserRole.manager ||
      managerId.isEmpty) {
    return Stream.value(const []);
  }
  return ref
      .watch(boxesRepositoryProvider)
      .watchAllBoxTransactions(managerId);
});

// الفواتير
final invoicesProvider = StreamProvider<List<InvoiceModel>>((ref) {
  final identity = ref.watch(_userIdentityProvider);
  final user = ref.read(currentUserProfileProvider).value;
  if (identity.uid == null || user == null) return Stream.value(const []);
  return ref.watch(invoicesRepositoryProvider).watchInvoicesForUser(user);
});

// المصاريف الشخصية
final personalExpensesProvider =
    StreamProvider<List<PersonalExpenseModel>>((ref) {
  final identity = ref.watch(_userIdentityProvider);
  final user = ref.read(currentUserProfileProvider).value;
  if (identity.uid == null || user == null) return Stream.value(const []);
  return ref.watch(expensesRepositoryProvider).watchExpensesForUser(user);
});

// سجل العمليات والإشعارات
final auditLogsProvider = StreamProvider<List<AuditLogModel>>((ref) {
  final identity = ref.watch(_userIdentityProvider);
  final user = ref.read(currentUserProfileProvider).value;
  if (identity.uid == null || user == null) return Stream.value(const []);
  return ref.watch(logsNotificationsRepositoryProvider).watchAuditLogs(user);
});

final notificationsProvider =
    StreamProvider<List<AppNotificationModel>>((ref) {
  final identity = ref.watch(_userIdentityProvider);
  final user = ref.read(currentUserProfileProvider).value;
  if (identity.uid == null || user == null) return Stream.value(const []);
  return ref
      .watch(logsNotificationsRepositoryProvider)
      .watchNotifications(user);
});

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final user = ref.watch(currentUserProfileProvider).value;
  final list = ref.watch(notificationsProvider).value ?? const [];
  if (user == null) return 0;
  return list.where((n) => !n.isReadBy(user.uid)).length;
});
