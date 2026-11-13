import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/server_time_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/master_data_models.dart';
import '../../models/monthly_box.dart';
import '../../providers/app_providers.dart';
import '../../widgets/browser_notification_widgets.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/month_year_picker.dart';
import 'monthly_box_detail_screen.dart';

class ManagerBoxesScreen extends ConsumerStatefulWidget {
  const ManagerBoxesScreen({super.key});

  @override
  ConsumerState<ManagerBoxesScreen> createState() => _ManagerBoxesScreenState();
}

class _ManagerBoxesScreenState extends ConsumerState<ManagerBoxesScreen> {
  int _sectionIndex = 0; // 0: الصناديق الشهرية، 1: صناديق المحافظات الفرعية

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final boxesAsync = ref.watch(monthlyBoxesProvider);
    final govBoxes =
        ref.watch(governorateMonthlyBoxesProvider).value ?? const [];
    final allTx = ref.watch(allBoxTransactionsProvider).value ?? const [];
    final companyTopUps = allTx
        .where((t) => t.type == BoxTransactionType.companyTopUp)
        .toList();
    final governorates = ref.watch(governoratesProvider).value ?? const [];
    final currentMonthKey = ref.watch(currentMonthKeyProvider).value;

    final boxes = List<MonthlyBox>.from(boxesAsync.value ?? const []);
    if (currentMonthKey != null &&
        !boxes.any((b) => b.monthKey == currentMonthKey)) {
      boxes.insert(0, MonthlyBox.empty(currentMonthKey));
    }
    boxes.sort((a, b) => b.monthKey.compareTo(a.monthKey));

    final generalBalance = boxes.fold<double>(
      0.0,
      (acc, b) => acc + b.currentBalance,
    );
    final totalTopUps = boxes.fold<double>(
      0.0,
      (acc, b) => acc + b.totalCompanyTopUps,
    );
    final totalDeductions = boxes.fold<double>(
      0.0,
      (acc, b) => acc + b.totalDeductions,
    );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          final user = ref.read(currentUserProfileProvider).value;
          if (user != null) {
            await ref
                .read(boxesRepositoryProvider)
                .ensureCurrentMonthBoxExists(user);
          }
        },
        child: ResponsivePageContainer(
          maxWidth: 1240,
          child: ListView(
            padding: ResponsiveBreakpoints.pagePadding(context),
            children: [
              const BrowserNotificationBanner(),
              BalanceHeroCard(
                title: l10n.tr('general_box'),
                subtitle: l10n.tr('general_box_desc'),
                balance: generalBalance,
                currency: l10n.tr('currency'),
                trailing: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => openCompanyTopUpDialog(
                    context: context,
                    ref: ref,
                    currentMonthKey: currentMonthKey,
                  ),
                  icon: const Icon(Icons.add_card_rounded, size: 18),
                  label: Text(l10n.tr('company_topup')),
                ),
                footerWidgets: [
                  _HeroStat(
                    label: l10n.tr('total_topups'),
                    value: AppFormatters.formatMoney(totalTopUps),
                  ),
                  _HeroStat(
                    label: l10n.tr('total_deductions'),
                    value: AppFormatters.formatMoney(totalDeductions),
                  ),
                  _HeroStat(
                    label: l10n.tr('monthly_boxes'),
                    value: '${boxes.length}',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ResponsiveCardGrid(
                maxColumns: 3,
                twoColumnsBreakpoint: 640,
                threeColumnsBreakpoint: 920,
                children: [
                  WebKpiCard(
                    label: l10n.tr('total_topups'),
                    value: AppFormatters.formatMoney(
                      totalTopUps,
                      currency: l10n.tr('currency'),
                    ),
                    icon: Icons.south_west_rounded,
                    color: AppTheme.successColor,
                  ),
                  WebKpiCard(
                    label: l10n.tr('total_deductions'),
                    value: AppFormatters.formatMoney(
                      totalDeductions,
                      currency: l10n.tr('currency'),
                    ),
                    icon: Icons.north_east_rounded,
                    color: AppTheme.dangerColor,
                  ),
                  WebKpiCard(
                    label: l10n.tr('gov_sub_boxes'),
                    value: '${governorates.length}',
                    icon: Icons.account_tree_outlined,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 0,
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text(l10n.tr('monthly_boxes')),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: const Icon(Icons.account_tree_outlined),
                      label: Text(l10n.tr('gov_sub_boxes')),
                    ),
                  ],
                  selected: {_sectionIndex},
                  onSelectionChanged: (s) =>
                      setState(() => _sectionIndex = s.first),
                ),
              ),
              const SizedBox(height: 18),
              if (_sectionIndex == 0) ...[
                if (boxesAsync.isLoading && boxes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (boxes.isEmpty)
                  EmptyStateWidget(
                    icon: Icons.account_balance_wallet_outlined,
                    message: l10n.tr('no_data'),
                  )
                else
                  ResponsiveCardGrid(
                    children: boxes
                        .map(
                          (box) => _MonthlyBoxCard(
                            box: box,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MonthlyBoxDetailScreen(
                                  monthKey: box.monthKey,
                                ),
                              ),
                            ),
                            onTopUp: () => openCompanyTopUpDialog(
                              context: context,
                              ref: ref,
                              currentMonthKey: currentMonthKey,
                              initialMonthKey: box.monthKey,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                if (companyTopUps.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    l10n.tr('company_topups_history'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  ResponsiveCardGrid(
                    maxColumns: 2,
                    twoColumnsBreakpoint: 760,
                    children: companyTopUps.map((tx) {
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.successColor
                                .withValues(alpha: 0.12),
                            child: const Icon(
                              Icons.arrow_downward_rounded,
                              color: AppTheme.successColor,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${tx.monthKey} • +${AppFormatters.formatMoney(tx.amount)} ${l10n.tr('currency')}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (tx.isEdited)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.warningColor
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    l10n.tr('edited_label'),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.warningColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${tx.performedByName}${tx.notes != null && tx.notes!.isNotEmpty ? " • ${tx.notes}" : ""}\n${tx.createdAt != null ? AppFormatters.formatDate(tx.createdAt!, includeTime: true) : ""}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: l10n.tr('edit_company_topup'),
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => openCompanyTopUpDialog(
                              context: context,
                              ref: ref,
                              existingTransaction: tx,
                            ),
                          ),
                          onTap: () => openCompanyTopUpDialog(
                            context: context,
                            ref: ref,
                            existingTransaction: tx,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ] else ...[
                if (governorates.isEmpty)
                  EmptyStateWidget(
                    icon: Icons.map_outlined,
                    message: l10n.tr('no_data'),
                  )
                else
                  ResponsiveCardGrid(
                    children: governorates.map((gov) {
                      final thisGovBoxes = govBoxes
                          .where((b) => b.governorateId == gov.id)
                          .toList();
                      final govBalance = thisGovBoxes.fold<double>(
                        0.0,
                        (acc, b) => acc + b.currentBalance,
                      );
                      final govTopUps = thisGovBoxes.fold<double>(
                        0.0,
                        (acc, b) => acc + b.totalTopUps,
                      );
                      final govDeductions = thisGovBoxes.fold<double>(
                        0.0,
                        (acc, b) => acc + b.totalDeductions,
                      );

                      return _GovernorateSubBoxCard(
                        governorate: gov,
                        balance: govBalance,
                        totalTopUps: govTopUps,
                        totalDeductions: govDeductions,
                        monthsCount: thisGovBoxes.length,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                GovernorateSubBoxScreen(governorate: gov),
                          ),
                        ),
                        onTopUp: () => openGovernorateTopUpDialog(
                          context: context,
                          ref: ref,
                          governorate: gov,
                          currentMonthKey: currentMonthKey,
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// نافذة تعبئة أو تعديل تعبئة صندوق شهري عام (يدعم اختيار الشهر الحالي أو أي شهر سابق)
void openCompanyTopUpDialog({
  required BuildContext context,
  required WidgetRef ref,
  String? currentMonthKey,
  String? initialMonthKey,
  BoxTransaction? existingTransaction,
}) {
  final l10n = AppLocalizations.of(context);
  final isEditing = existingTransaction != null;
  final amountText = existingTransaction != null
      ? (existingTransaction.amount == existingTransaction.amount.roundToDouble()
          ? existingTransaction.amount.toStringAsFixed(0)
          : existingTransaction.amount.toString())
      : '';
  final amountCtrl = TextEditingController(text: amountText);
  final notesCtrl =
      TextEditingController(text: existingTransaction?.notes ?? '');
  final formKey = GlobalKey<FormState>();

  final nowDate = DateTime.now();
  final seedKey =
      existingTransaction?.monthKey ??
      initialMonthKey ??
      currentMonthKey ??
      ServerTimeService.toMonthKey(nowDate);
  final parsedSeed = ServerTimeService.parseMonthKey(seedKey);

  int selectedYear = parsedSeed.year;
  int selectedMonth = parsedSeed.month;
  bool busy = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          l10n.tr(isEditing ? 'edit_company_topup' : 'company_topup'),
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MonthYearSelectorRow(
                  selectedYear: selectedYear,
                  selectedMonth: selectedMonth,
                  maxYear: nowDate.year + 1,
                  onYearChanged: (y) => setState(() => selectedYear = y),
                  onMonthChanged: (m) => setState(() => selectedMonth = m),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.tr('amount'),
                    suffixText: l10n.tr('currency'),
                  ),
                  validator: (v) {
                    final val = double.tryParse(v?.trim() ?? '');
                    if (val == null || val <= 0) {
                      return l10n.tr('required_field');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration: InputDecoration(labelText: l10n.tr('notes')),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    final manager = ref.read(currentUserProfileProvider).value;
                    if (manager == null) return;
                    setState(() => busy = true);
                    try {
                      final mKey = MonthYearSelectorRow.toMonthKey(
                        selectedYear,
                        selectedMonth,
                      );
                      final amount = double.parse(amountCtrl.text.trim());
                      final notes = notesCtrl.text.trim();
                      final repo = ref.read(boxesRepositoryProvider);
                      if (isEditing) {
                        await repo.editCompanyTopUp(
                          manager: manager,
                          oldTx: existingTransaction,
                          newMonthKey: mKey,
                          newAmount: amount,
                          notes: notes,
                        );
                      } else {
                        await repo.topUpMonthlyBoxFromCompany(
                          manager: manager,
                          monthKey: mKey,
                          amount: amount,
                          notes: notes,
                        );
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    } finally {
                      if (ctx.mounted) setState(() => busy = false);
                    }
                  },
            child: Text(l10n.tr('confirm')),
          ),
        ],
      ),
    ),
  );
}

/// نافذة تعبئة صندوق محافظة فرعي لشهر محدد (يدعم الأشهر الحالية والسابقة)
void openGovernorateTopUpDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Governorate governorate,
  String? currentMonthKey,
  String? initialMonthKey,
}) {
  final l10n = AppLocalizations.of(context);
  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final nowDate = DateTime.now();
  final seedKey =
      initialMonthKey ??
      currentMonthKey ??
      ServerTimeService.toMonthKey(nowDate);
  final parsedSeed = ServerTimeService.parseMonthKey(seedKey);

  int selectedYear = parsedSeed.year;
  int selectedMonth = parsedSeed.month;
  bool busy = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          '${l10n.tr('topup_governorate')} • ${governorate.displayName(l10n.isAr)}',
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MonthYearSelectorRow(
                  selectedYear: selectedYear,
                  selectedMonth: selectedMonth,
                  maxYear: nowDate.year + 1,
                  onYearChanged: (y) => setState(() => selectedYear = y),
                  onMonthChanged: (m) => setState(() => selectedMonth = m),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.tr('amount'),
                    suffixText: l10n.tr('currency'),
                  ),
                  validator: (v) {
                    final val = double.tryParse(v?.trim() ?? '');
                    if (val == null || val <= 0) {
                      return l10n.tr('required_field');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration: InputDecoration(labelText: l10n.tr('notes')),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    final manager = ref.read(currentUserProfileProvider).value;
                    if (manager == null) return;
                    setState(() => busy = true);
                    try {
                      final mKey = MonthYearSelectorRow.toMonthKey(
                        selectedYear,
                        selectedMonth,
                      );
                      await ref
                          .read(boxesRepositoryProvider)
                          .topUpGovernorateMonthlyBox(
                            manager: manager,
                            governorateId: governorate.id,
                            governorateName: governorate.displayName(l10n.isAr),
                            monthKey: mKey,
                            amount: double.parse(amountCtrl.text.trim()),
                            notes: notesCtrl.text.trim(),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    } finally {
                      if (ctx.mounted) setState(() => busy = false);
                    }
                  },
            child: Text(l10n.tr('confirm')),
          ),
        ],
      ),
    ),
  );
}

class GovernorateSubBoxScreen extends ConsumerWidget {
  const GovernorateSubBoxScreen({super.key, required this.governorate});

  final Governorate governorate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final allGovBoxes =
        ref.watch(governorateMonthlyBoxesProvider).value ?? const [];
    final currentMonthKey = ref.watch(currentMonthKeyProvider).value;

    final govBoxes = allGovBoxes
        .where((b) => b.governorateId == governorate.id)
        .toList();
    if (currentMonthKey != null &&
        !govBoxes.any((b) => b.monthKey == currentMonthKey)) {
      govBoxes.insert(
        0,
        GovernorateMonthlyBox.empty(
          governorateId: governorate.id,
          governorateName: governorate.displayName(l10n.isAr),
          monthKey: currentMonthKey,
        ),
      );
    }
    govBoxes.sort((a, b) => b.monthKey.compareTo(a.monthKey));

    final totalBalance = govBoxes.fold<double>(
      0.0,
      (acc, b) => acc + b.currentBalance,
    );
    final totalTopUps = govBoxes.fold<double>(
      0.0,
      (acc, b) => acc + b.totalTopUps,
    );
    final totalDeductions = govBoxes.fold<double>(
      0.0,
      (acc, b) => acc + b.totalDeductions,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${l10n.tr('manager_gov_box')} • ${governorate.displayName(l10n.isAr)}',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openGovernorateTopUpDialog(
          context: context,
          ref: ref,
          governorate: governorate,
          currentMonthKey: currentMonthKey,
        ),
        icon: const Icon(Icons.add_card_rounded),
        label: Text(l10n.tr('topup_governorate')),
      ),
      body: ResponsivePageContainer(
        maxWidth: 1200,
        child: ListView(
          padding: ResponsiveBreakpoints.pagePadding(context, withFab: true),
          children: [
            BalanceHeroCard(
              title: governorate.displayName(l10n.isAr),
              subtitle: l10n.tr('manager_gov_box'),
              balance: totalBalance,
              currency: l10n.tr('currency'),
              footerWidgets: [
                _HeroStat(
                  label: l10n.tr('manager_allocations'),
                  value: AppFormatters.formatMoney(totalTopUps),
                ),
                _HeroStat(
                  label: l10n.tr('total_deductions'),
                  value: AppFormatters.formatMoney(totalDeductions),
                ),
                _HeroStat(
                  label: l10n.tr('monthly_boxes'),
                  value: '${govBoxes.length}',
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (govBoxes.isEmpty)
              EmptyStateWidget(
                icon: Icons.account_balance_wallet_outlined,
                message: l10n.tr('gov_sub_box_empty'),
              )
            else
              ResponsiveCardGrid(
                children: govBoxes.map((box) {
                  final isNeg = box.currentBalance < 0;
                  final balColor = isNeg
                      ? AppTheme.dangerColor
                      : AppTheme.successColor;
                  return Card(
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MonthlyBoxDetailScreen(
                            monthKey: box.monthKey,
                            governorate: governorate,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: balColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  child: Text(
                                    '${box.month}',
                                    style: TextStyle(
                                      color: balColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        box.label(l10n.isAr),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        '${l10n.tr('manager_allocations')}: ${AppFormatters.formatMoney(box.totalTopUps)} • ${l10n.tr('total_deductions')}: ${AppFormatters.formatMoney(box.totalDeductions)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton.filledTonal(
                                  tooltip: l10n.tr('topup_governorate'),
                                  onPressed: () => openGovernorateTopUpDialog(
                                    context: context,
                                    ref: ref,
                                    governorate: governorate,
                                    currentMonthKey: currentMonthKey,
                                    initialMonthKey: box.monthKey,
                                  ),
                                  icon: const Icon(Icons.add_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(l10n.tr('current_balance')),
                                Text(
                                  AppFormatters.formatMoney(
                                    box.currentBalance,
                                    currency: l10n.tr('currency'),
                                  ),
                                  style: TextStyle(
                                    color: balColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _GovernorateSubBoxCard extends StatelessWidget {
  const _GovernorateSubBoxCard({
    required this.governorate,
    required this.balance,
    required this.totalTopUps,
    required this.totalDeductions,
    required this.monthsCount,
    required this.onTap,
    required this.onTopUp,
  });

  final Governorate governorate;
  final double balance;
  final double totalTopUps;
  final double totalDeductions;
  final int monthsCount;
  final VoidCallback onTap;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isNeg = balance < 0;
    final balColor = isNeg ? AppTheme.dangerColor : AppTheme.successColor;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: balColor.withValues(alpha: 0.12),
                    child: Icon(Icons.location_city_rounded, color: balColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          governorate.displayName(l10n.isAr),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${l10n.tr('manager_allocations')}: ${AppFormatters.formatMoney(totalTopUps)} • ${l10n.tr('total_deductions')}: ${AppFormatters.formatMoney(totalDeductions)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: l10n.tr('topup_governorate'),
                    onPressed: onTopUp,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${l10n.tr('current_balance')} ($monthsCount ${l10n.tr('monthly_boxes')})',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    AppFormatters.formatMoney(
                      balance,
                      currency: l10n.tr('currency'),
                    ),
                    style: TextStyle(
                      color: balColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyBoxCard extends StatelessWidget {
  const _MonthlyBoxCard({
    required this.box,
    required this.onTap,
    required this.onTopUp,
  });

  final MonthlyBox box;
  final VoidCallback onTap;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isNeg = box.currentBalance < 0;
    final balColor = isNeg ? AppTheme.dangerColor : AppTheme.successColor;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: balColor.withValues(alpha: 0.12),
                    child: Text(
                      '${box.month}',
                      style: TextStyle(
                        color: balColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          box.label(l10n.isAr),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${l10n.tr('total_topups')}: ${AppFormatters.formatMoney(box.totalCompanyTopUps)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: l10n.tr('company_topup'),
                    onPressed: onTopUp,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.tr('current_balance'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    AppFormatters.formatMoney(
                      box.currentBalance,
                      currency: l10n.tr('currency'),
                    ),
                    style: TextStyle(
                      color: balColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
              if (isNeg) ...[
                const SizedBox(height: 8),
                StatusBadge(
                  label: l10n.tr('negative_balance_warning'),
                  color: AppTheme.dangerColor,
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
