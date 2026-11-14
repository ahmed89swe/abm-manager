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
        .where(
          (t) =>
              t.type == BoxTransactionType.companyTopUp ||
              t.type == BoxTransactionType.governorateTopUp ||
              t.isDelegateVirtualTx,
        )
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
                      final isCompany =
                          tx.type == BoxTransactionType.companyTopUp;
                      final isGovTopUp =
                          tx.type == BoxTransactionType.governorateTopUp;
                      final isEditableDelegateTx = tx.type ==
                              BoxTransactionType.delegateVirtualTopUp ||
                          tx.type == BoxTransactionType.delegateVirtualWithdraw;
                      final isPositive = tx.effectiveSignedDelta >= 0;
                      final txColor = isPositive
                          ? AppTheme.successColor
                          : AppTheme.dangerColor;
                      final sign = isPositive ? '+' : '-';

                      String typeLabel;
                      if (isCompany) {
                        typeLabel = l10n.tr('company_topup');
                      } else if (isGovTopUp) {
                        typeLabel = l10n.tr('topup_governorate');
                      } else if (tx.type ==
                          BoxTransactionType.delegateVirtualWithdraw) {
                        typeLabel = l10n.tr('delegate_virtual_withdraw');
                      } else if (tx.type ==
                          BoxTransactionType.delegateVirtualAdjustment) {
                        typeLabel = l10n.tr('delegate_virtual_adjustment');
                      } else {
                        typeLabel = l10n.tr('topup_delegate');
                      }

                      final targetParts = <String>[
                        typeLabel,
                        if ((tx.governorateName ?? '').isNotEmpty)
                          tx.governorateName!,
                        if ((tx.delegateName ?? '').isNotEmpty)
                          tx.delegateName!,
                        tx.performedByName,
                        if (tx.notes != null && tx.notes!.isNotEmpty) tx.notes!,
                      ];

                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: txColor.withValues(alpha: 0.12),
                            child: Icon(
                              isPositive
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color: txColor,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${tx.monthKey} • $sign${AppFormatters.formatMoney(tx.amount)} ${l10n.tr('currency')}',
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
                            '${targetParts.join(" • ")}\n${tx.createdAt != null ? AppFormatters.formatDate(tx.createdAt!, includeTime: true) : ""}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCompany)
                                IconButton(
                                  tooltip: l10n.tr('edit_company_topup'),
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => openCompanyTopUpDialog(
                                    context: context,
                                    ref: ref,
                                    existingTransaction: tx,
                                  ),
                                )
                              else if (isEditableDelegateTx)
                                IconButton(
                                  tooltip: l10n.tr('edit_delegate_tx'),
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => openEditDelegateBoxTxDialog(
                                    context: context,
                                    ref: ref,
                                    existingTransaction: tx,
                                  ),
                                ),
                              IconButton(
                                tooltip: l10n.tr('delete_topup'),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppTheme.dangerColor,
                                ),
                                onPressed: () => confirmAndDeleteTopUpTransaction(
                                  context,
                                  ref,
                                  tx,
                                ),
                              ),
                            ],
                          ),
                          onTap: isCompany
                              ? () => openCompanyTopUpDialog(
                                    context: context,
                                    ref: ref,
                                    existingTransaction: tx,
                                  )
                              : isEditableDelegateTx
                                  ? () => openEditDelegateBoxTxDialog(
                                        context: context,
                                        ref: ref,
                                        existingTransaction: tx,
                                      )
                                  : null,
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

/// نافذة تأكيد حذف أي عملية تعبئة وعكس أثرها المالي على الصناديق المرتبطة
Future<bool> confirmAndDeleteTopUpTransaction(
  BuildContext context,
  WidgetRef ref,
  BoxTransaction txDoc,
) async {
  final l10n = AppLocalizations.of(context);
  final manager = ref.read(currentUserProfileProvider).value;
  if (manager == null || !manager.isManager) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);

  final targetInfo = <String>[
    '${l10n.tr('amount')}: ${AppFormatters.formatMoney(txDoc.amount, currency: l10n.tr('currency'))}',
    '${l10n.tr('select_month')}: ${AppFormatters.formatMonthLabel(txDoc.monthKey, isAr: l10n.isAr)}',
    if ((txDoc.governorateName ?? '').isNotEmpty)
      '${l10n.tr('governorate')}: ${txDoc.governorateName}',
    if ((txDoc.delegateName ?? '').isNotEmpty)
      '${l10n.tr('delegate_name')}: ${txDoc.delegateName}',
  ].join('\n');

  final isDelegateCustomTx =
      txDoc.type == BoxTransactionType.delegateVirtualWithdraw ||
          txDoc.type == BoxTransactionType.delegateVirtualAdjustment;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(
        isDelegateCustomTx
            ? l10n.tr('delete')
            : l10n.tr('delete_topup'),
      ),
      content: Text(
        '${isDelegateCustomTx ? l10n.tr('delete_delegate_tx_confirm') : l10n.tr('delete_topup_confirm')}\n\n$targetInfo',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx, false),
          child: Text(l10n.tr('cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.dangerColor,
          ),
          onPressed: () => Navigator.pop(dCtx, true),
          child: Text(l10n.tr('delete')),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await ref.read(boxesRepositoryProvider).deleteTopUpTransaction(
          manager: manager,
          txDoc: txDoc,
        );
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.tr('topup_deleted'))),
    );
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}

/// نافذة تعبئة أو تعديل تعبئة صندوق شهري من الشركة (بتحديد المحافظة والشهر)
void openCompanyTopUpDialog({
  required BuildContext context,
  required WidgetRef ref,
  String? currentMonthKey,
  String? initialMonthKey,
  String? initialGovernorateId,
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
  String? selectedGovId = existingTransaction?.governorateId ?? initialGovernorateId;
  bool didInitGov = false;
  bool busy = false;

  showDialog(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, dialogRef, _) {
        final governorates =
            dialogRef.watch(governoratesProvider).value ?? const <Governorate>[];
        if (!didInitGov) {
          didInitGov = true;
          if (selectedGovId != null &&
              !governorates.any((g) => g.id == selectedGovId)) {
            selectedGovId = null;
          }
          if (!isEditing && selectedGovId == null && governorates.length == 1) {
            selectedGovId = governorates.first.id;
          }
        }

        return StatefulBuilder(
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
                    if (governorates.isNotEmpty) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: governorates.any((g) => g.id == selectedGovId)
                            ? selectedGovId
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: '${l10n.tr('governorate')} *',
                          prefixIcon: const Icon(Icons.location_city_outlined),
                        ),
                        items: [
                          if (isEditing &&
                              (existingTransaction.governorateId ?? '').isEmpty)
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(l10n.tr('no_governorate_legacy')),
                            ),
                          ...governorates.map(
                            (g) => DropdownMenuItem<String?>(
                              value: g.id,
                              child: Text(g.displayName(l10n.isAr)),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => selectedGovId = v),
                        validator: (v) {
                          if (isEditing &&
                              (existingTransaction.governorateId ?? '').isEmpty) {
                            return null;
                          }
                          if (governorates.isNotEmpty &&
                              (v == null || v.isEmpty)) {
                            return l10n.tr('required_field');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
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
                        final manager =
                            ref.read(currentUserProfileProvider).value;
                        if (manager == null) return;
                        setState(() => busy = true);
                        try {
                          final mKey = MonthYearSelectorRow.toMonthKey(
                            selectedYear,
                            selectedMonth,
                          );
                          final amount = double.parse(amountCtrl.text.trim());
                          final notes = notesCtrl.text.trim();
                          Governorate? pickedGov;
                          if (selectedGovId != null) {
                            for (final g in governorates) {
                              if (g.id == selectedGovId) {
                                pickedGov = g;
                                break;
                              }
                            }
                          }
                          final govId = pickedGov?.id;
                          final govName = pickedGov?.displayName(l10n.isAr);

                          final repo = ref.read(boxesRepositoryProvider);
                          if (isEditing) {
                            await repo.editCompanyTopUp(
                              manager: manager,
                              oldTx: existingTransaction,
                              newMonthKey: mKey,
                              newAmount: amount,
                              newGovernorateId: govId,
                              newGovernorateName: govName,
                              notes: notes,
                            );
                          } else {
                            await repo.topUpMonthlyBoxFromCompany(
                              manager: manager,
                              monthKey: mKey,
                              amount: amount,
                              governorateId: govId,
                              governorateName: govName,
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
        );
      },
    ),
  );
}

/// نافذة تعبئة صندوق محافظة لشهر محدد (مع خيار إضافته للصندوق الشهري العام أيضاً)
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
  String selectedGovId = governorate.id;
  bool alsoCreditCompanyBox = true;
  bool busy = false;

  showDialog(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, dialogRef, _) {
        final governorates =
            dialogRef.watch(governoratesProvider).value ?? [governorate];
        if (!governorates.any((g) => g.id == selectedGovId)) {
          governorates.add(governorate);
        }

        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(l10n.tr('topup_governorate')),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedGovId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: '${l10n.tr('governorate')} *',
                        prefixIcon: const Icon(Icons.location_city_outlined),
                      ),
                      items: governorates
                          .map(
                            (g) => DropdownMenuItem<String>(
                              value: g.id,
                              child: Text(g.displayName(l10n.isAr)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => selectedGovId = v);
                      },
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l10n.tr('also_credit_general_box'),
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        l10n.tr('also_credit_general_box_hint'),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      value: alsoCreditCompanyBox,
                      onChanged: (v) =>
                          setState(() => alsoCreditCompanyBox = v),
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
                        final manager =
                            ref.read(currentUserProfileProvider).value;
                        if (manager == null) return;
                        setState(() => busy = true);
                        try {
                          final mKey = MonthYearSelectorRow.toMonthKey(
                            selectedYear,
                            selectedMonth,
                          );
                          final pickedGov = governorates.firstWhere(
                            (g) => g.id == selectedGovId,
                            orElse: () => governorate,
                          );
                          final govName = pickedGov.displayName(l10n.isAr);
                          final amount = double.parse(amountCtrl.text.trim());
                          final notes = notesCtrl.text.trim();
                          final repo = ref.read(boxesRepositoryProvider);

                          if (alsoCreditCompanyBox) {
                            await repo.topUpMonthlyBoxFromCompany(
                              manager: manager,
                              monthKey: mKey,
                              amount: amount,
                              governorateId: pickedGov.id,
                              governorateName: govName,
                              notes: notes,
                            );
                          } else {
                            await repo.topUpGovernorateMonthlyBox(
                              manager: manager,
                              governorateId: pickedGov.id,
                              governorateName: govName,
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
        );
      },
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

/// نافذة تعديل حركة تعبئة أو سحب سابقة على الصندوق الافتراضي للمندوب
Future<void> openEditDelegateBoxTxDialog({
  required BuildContext context,
  required WidgetRef ref,
  required BoxTransaction existingTransaction,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final parsed = ServerTimeService.parseMonthKey(existingTransaction.monthKey);
  int selectedYear = parsed.year;
  int selectedMonth = parsed.month;
  final amountCtrl = TextEditingController(
    text: existingTransaction.amount.toStringAsFixed(0),
  );
  final notesCtrl =
      TextEditingController(text: existingTransaction.notes ?? '');
  final formKey = GlobalKey<FormState>();
  final nowYear = DateTime.now().year;
  bool busy = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          '${l10n.tr('edit_delegate_tx')} • ${existingTransaction.delegateName ?? ''}',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 440),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MonthYearSelectorRow(
                    selectedYear: selectedYear,
                    selectedMonth: selectedMonth,
                    maxYear: nowYear + 1,
                    onYearChanged: (y) => setState(() => selectedYear = y),
                    onMonthChanged: (m) => setState(() => selectedMonth = m),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.tr('amount'),
                      suffixText: l10n.tr('currency'),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      return (n == null || n <= 0)
                          ? l10n.tr('required_field')
                          : null;
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
                      final newMonthKey = ServerTimeService.toMonthKey(
                        DateTime(selectedYear, selectedMonth, 1),
                      );
                      await ref
                          .read(boxesRepositoryProvider)
                          .editDelegateVirtualTransaction(
                            manager: manager,
                            oldTx: existingTransaction,
                            newMonthKey: newMonthKey,
                            newAmount: double.parse(amountCtrl.text.trim()),
                            notes: notesCtrl.text.trim(),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(l10n.tr('delegate_balance_updated')),
                        ),
                      );
                    } catch (e) {
                      messenger?.showSnackBar(SnackBar(content: Text('$e')));
                    } finally {
                      if (ctx.mounted) setState(() => busy = false);
                    }
                  },
            child: Text(l10n.tr('save')),
          ),
        ],
      ),
    ),
  );
}
