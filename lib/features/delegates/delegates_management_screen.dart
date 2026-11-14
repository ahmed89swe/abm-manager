import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/server_time_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/master_data_models.dart';
import '../../models/monthly_box.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/month_year_picker.dart';
import '../../widgets/user_avatar_widget.dart';
import '../boxes/manager_boxes_screen.dart';

class DelegatesManagementScreen extends ConsumerStatefulWidget {
  const DelegatesManagementScreen({super.key});

  @override
  ConsumerState<DelegatesManagementScreen> createState() =>
      _DelegatesManagementScreenState();
}

class _DelegatesManagementScreenState
    extends ConsumerState<DelegatesManagementScreen> {
  String? _filterGovernorateId;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final delegatesAsync = ref.watch(delegatesProvider);
    final governorates = ref.watch(governoratesProvider).value ?? const [];

    var delegates = delegatesAsync.value ?? const <AppUser>[];
    if (_filterGovernorateId != null) {
      delegates = delegates
          .where((d) => d.governorateId == _filterGovernorateId)
          .toList();
    }
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      delegates = delegates
          .where((d) =>
              d.name.toLowerCase().contains(q) ||
              d.email.toLowerCase().contains(q) ||
              (d.governorateName ?? '').toLowerCase().contains(q))
          .toList();
    }

    final allDelegates = delegatesAsync.value ?? const <AppUser>[];
    final activeCount = allDelegates.where((d) => d.isActive).length;
    final totalVirtualBalances =
        allDelegates.fold<double>(0.0, (a, b) => a + b.virtualBoxBalance);

    return Scaffold(
      body: ResponsivePageContainer(
        maxWidth: 1240,
        child: ListView(
          padding: ResponsiveBreakpoints.pagePadding(context, withFab: true),
          children: [
            ResponsiveCardGrid(
              maxColumns: 3,
              twoColumnsBreakpoint: 620,
              threeColumnsBreakpoint: 900,
              children: [
                WebKpiCard(
                  label: l10n.tr('delegates'),
                  value: '${allDelegates.length}',
                  icon: Icons.people_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                WebKpiCard(
                  label: l10n.tr('active'),
                  value: '$activeCount',
                  icon: Icons.verified_user_outlined,
                  color: AppTheme.successColor,
                ),
                WebKpiCard(
                  label: l10n.tr('delegate_boxes'),
                  value: AppFormatters.formatMoney(
                    totalVirtualBalances,
                    currency: l10n.tr('currency'),
                  ),
                  icon: Icons.account_balance_wallet_outlined,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 500;
                final searchField = TextField(
                  decoration: InputDecoration(
                    hintText: l10n.tr('search'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                );
                final govDropdown = DropdownButtonFormField<String?>(
                  initialValue: _filterGovernorateId,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: l10n.tr('governorate')),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.tr('all')),
                    ),
                    ...governorates.map(
                      (g) => DropdownMenuItem<String?>(
                        value: g.id,
                        child: Text(g.displayName(l10n.isAr)),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _filterGovernorateId = v),
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      searchField,
                      const SizedBox(height: 10),
                      govDropdown,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 3, child: searchField),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: govDropdown),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (delegatesAsync.isLoading && delegates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (delegates.isEmpty)
              EmptyStateWidget(
                icon: Icons.people_outline_rounded,
                message: l10n.tr('no_data'),
              )
            else
              ResponsiveCardGrid(
                children: delegates.map((d) {
                  final isNeg = d.virtualBoxBalance < 0;
                  return Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              UserAvatarWidget(user: d, radius: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      '${d.governorateName ?? "-"} • ${d.email}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              StatusBadge(
                                label: d.isActive
                                    ? l10n.tr('active')
                                    : l10n.tr('inactive'),
                                color: d.isActive
                                    ? AppTheme.successColor
                                    : AppTheme.dangerColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(l10n.tr('current_balance')),
                                Flexible(
                                  child: Text(
                                    AppFormatters.formatMoney(
                                      d.virtualBoxBalance,
                                      currency: l10n.tr('currency'),
                                    ),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: isNeg
                                          ? AppTheme.dangerColor
                                          : AppTheme.successColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _openTopUpDelegateDialog(d),
                                  icon: const Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    l10n.tr('topup_delegate'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _openWithdrawOrAdjustDialog(d),
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    l10n.tr('withdraw_delegate_balance'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _showDelegateBoxHistorySheet(d),
                                  icon: const Icon(
                                    Icons.history_rounded,
                                    size: 18,
                                  ),
                                  label: Text(l10n.tr('delegate_box_history')),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                tooltip: l10n.isAr
                                    ? 'تعديل المندوب'
                                    : 'Edit Delegate',
                                onPressed: () => _openCreateOrEditDialog(
                                  governorates,
                                  existing: d,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateOrEditDialog(governorates),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l10n.tr('add_delegate')),
      ),
    );
  }

  void _openTopUpDelegateDialog(AppUser delegate) {
    final l10n = AppLocalizations.of(context);
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final nowDate = DateTime.now();
    int selectedYear = nowDate.year;
    int selectedMonth = nowDate.month;
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('${l10n.tr('topup_delegate')}: ${delegate.name}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
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
                        final monthKey = ServerTimeService.toMonthKey(
                          DateTime(selectedYear, selectedMonth, 1),
                        );
                        await ref
                            .read(boxesRepositoryProvider)
                            .topUpDelegateVirtualBox(
                              manager: manager,
                              delegate: delegate,
                              amount: double.parse(amountCtrl.text.trim()),
                              monthKeyOverride: monthKey,
                              notes: notesCtrl.text.trim(),
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
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

  void _openWithdrawOrAdjustDialog(AppUser delegate) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final inputCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final nowDate = DateTime.now();
    int selectedYear = nowDate.year;
    int selectedMonth = nowDate.month;
    String mode = 'withdraw'; // withdraw | adjust
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final parsedVal = double.tryParse(inputCtrl.text.trim()) ?? 0;
          final resultingBalance = mode == 'withdraw'
              ? (delegate.virtualBoxBalance - parsedVal)
              : parsedVal;
          final delta = resultingBalance - delegate.virtualBoxBalance;

          return AlertDialog(
            title: Text(
              '${l10n.tr('withdraw_delegate_balance')}: ${delegate.name}',
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 300, maxWidth: 440),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'withdraw',
                            icon: const Icon(Icons.remove_circle_outline),
                            label: Text(l10n.tr('withdraw_from_delegate')),
                          ),
                          ButtonSegment(
                            value: 'adjust',
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(l10n.tr('edit_delegate_balance')),
                          ),
                        ],
                        selected: {mode},
                        onSelectionChanged: (sel) {
                          setState(() {
                            mode = sel.first;
                            if (mode == 'adjust') {
                              inputCtrl.text =
                                  delegate.virtualBoxBalance.toStringAsFixed(0);
                            } else {
                              inputCtrl.clear();
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${l10n.tr('current_balance')}: ${AppFormatters.formatMoney(delegate.virtualBoxBalance, currency: l10n.tr('currency'))}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${l10n.tr('new_balance')}: ${AppFormatters.formatMoney(resultingBalance, currency: l10n.tr('currency'))} (${delta >= 0 ? '+' : ''}${AppFormatters.formatMoney(delta)})',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: resultingBalance < 0
                                    ? AppTheme.dangerColor
                                    : AppTheme.successColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      MonthYearSelectorRow(
                        selectedYear: selectedYear,
                        selectedMonth: selectedMonth,
                        maxYear: nowDate.year + 1,
                        onYearChanged: (y) => setState(() => selectedYear = y),
                        onMonthChanged: (m) =>
                            setState(() => selectedMonth = m),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: inputCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: mode == 'withdraw'
                              ? l10n.tr('withdraw_amount')
                              : l10n.tr('new_balance'),
                          suffixText: l10n.tr('currency'),
                        ),
                        validator: (v) {
                          final n = double.tryParse(v?.trim() ?? '');
                          if (n == null) return l10n.tr('required_field');
                          if (mode == 'withdraw' && n <= 0) {
                            return l10n.tr('required_field');
                          }
                          if (mode == 'adjust' &&
                              (n - delegate.virtualBoxBalance).abs() < 0.0001) {
                            return l10n.isAr
                                ? 'الرصيد الجديد مطابق للرصيد الحالي'
                                : 'New balance matches current balance';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.tr('notes'),
                        ),
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
                        final manager =
                            ref.read(currentUserProfileProvider).value;
                        if (manager == null) return;
                        setState(() => busy = true);
                        try {
                          final monthKey = ServerTimeService.toMonthKey(
                            DateTime(selectedYear, selectedMonth, 1),
                          );
                          final val = double.parse(inputCtrl.text.trim());
                          final repo = ref.read(boxesRepositoryProvider);
                          if (mode == 'withdraw') {
                            await repo.withdrawFromDelegateVirtualBox(
                              manager: manager,
                              delegate: delegate,
                              amount: val,
                              monthKeyOverride: monthKey,
                              notes: notesCtrl.text.trim(),
                            );
                          } else {
                            await repo.adjustDelegateVirtualBalance(
                              manager: manager,
                              delegate: delegate,
                              newBalance: val,
                              monthKeyOverride: monthKey,
                              notes: notesCtrl.text.trim(),
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          messenger?.showSnackBar(
                            SnackBar(
                              content: Text(
                                mode == 'withdraw'
                                    ? l10n.tr('delegate_withdraw_success')
                                    : l10n.tr('delegate_balance_updated'),
                              ),
                            ),
                          );
                        } catch (e) {
                          messenger?.showSnackBar(SnackBar(content: Text('$e')));
                        } finally {
                          if (ctx.mounted) setState(() => busy = false);
                        }
                      },
                child: Text(l10n.tr('confirm')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDelegateBoxHistorySheet(AppUser delegate) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sCtx) => Consumer(
        builder: (sCtx, sRef, _) {
          final delegates = sRef.watch(delegatesProvider).value ?? const [];
          final liveDelegate = delegates.firstWhere(
            (d) => d.uid == delegate.uid,
            orElse: () => delegate,
          );
          final allTx =
              sRef.watch(allBoxTransactionsProvider).value ?? const [];
          final delegateTxs = allTx
              .where(
                (t) => t.delegateId == delegate.uid && t.isDelegateVirtualTx,
              )
              .toList();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            builder: (_, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${l10n.tr('delegate_box_history')} • ${liveDelegate.name}',
                              style: Theme.of(sCtx)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${l10n.tr('current_balance')}: ${AppFormatters.formatMoney(liveDelegate.virtualBoxBalance, currency: l10n.tr('currency'))}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: liveDelegate.virtualBoxBalance < 0
                                    ? AppTheme.dangerColor
                                    : AppTheme.successColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sCtx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: delegateTxs.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.history_rounded,
                          message: l10n.tr('no_data'),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          itemCount: delegateTxs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, idx) {
                            final tx = delegateTxs[idx];
                            final isPositive = tx.effectiveSignedDelta >= 0;
                            final color = isPositive
                                ? AppTheme.successColor
                                : AppTheme.dangerColor;
                            final sign = isPositive ? '+' : '-';
                            final isEditable =
                                tx.type ==
                                        BoxTransactionType
                                            .delegateVirtualTopUp ||
                                    tx.type ==
                                        BoxTransactionType
                                            .delegateVirtualWithdraw;

                            final title = tx.type ==
                                    BoxTransactionType.delegateVirtualWithdraw
                                ? l10n.tr('delegate_virtual_withdraw')
                                : tx.type ==
                                        BoxTransactionType
                                            .delegateVirtualAdjustment
                                    ? l10n.tr('delegate_virtual_adjustment')
                                    : l10n.tr('topup_delegate');

                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      color.withValues(alpha: 0.12),
                                  child: Icon(
                                    isPositive
                                        ? Icons.arrow_downward_rounded
                                        : Icons.arrow_upward_rounded,
                                    color: color,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$title • $sign${AppFormatters.formatMoney(tx.amount)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (tx.isEdited)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.warningColor
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          l10n.tr('edited_label'),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.warningColor,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  '${tx.monthKey}${tx.notes != null && tx.notes!.isNotEmpty ? " • ${tx.notes}" : ""}\n${tx.createdAt != null ? AppFormatters.formatDate(tx.createdAt!, includeTime: true) : ""}',
                                ),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isEditable)
                                      IconButton(
                                        tooltip: l10n.tr('edit_delegate_tx'),
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () =>
                                            openEditDelegateBoxTxDialog(
                                          context: sCtx,
                                          ref: sRef,
                                          existingTransaction: tx,
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: l10n.tr('delete'),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: AppTheme.dangerColor,
                                      ),
                                      onPressed: () =>
                                          confirmAndDeleteTopUpTransaction(
                                        sCtx,
                                        sRef,
                                        tx,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openCreateOrEditDialog(
    List<Governorate> governorates, {
    AppUser? existing,
  }) {
    final l10n = AppLocalizations.of(context);
    if (governorates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.isAr
                ? 'يرجى إضافة محافظة واحدة على الأقل من تبويب الثوابت أولاً'
                : 'Please add at least one governorate in Master Data first',
          ),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final passCtrl = TextEditingController();
    final initBalCtrl = TextEditingController(text: '0');

    String selectedGovId = existing?.governorateId ?? governorates.first.id;
    bool isActive = existing?.isActive ?? true;
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null
                ? l10n.tr('add_delegate')
                : (l10n.isAr ? 'تعديل المندوب' : 'Edit Delegate'),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration:
                        InputDecoration(labelText: l10n.tr('delegate_name')),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.tr('required_field')
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: governorates.any((g) => g.id == selectedGovId)
                        ? selectedGovId
                        : governorates.first.id,
                    isExpanded: true,
                    decoration:
                        InputDecoration(labelText: l10n.tr('governorate')),
                    items: governorates
                        .map(
                          (g) => DropdownMenuItem(
                            value: g.id,
                            child: Text(g.displayName(l10n.isAr)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => selectedGovId = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: l10n.tr('phone')),
                  ),
                  if (existing == null) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: l10n.tr('email')),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? l10n.tr('required_field')
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration:
                          InputDecoration(labelText: l10n.tr('password')),
                      validator: (v) => (v == null || v.length < 6)
                          ? (l10n.isAr ? '6 أحرف على الأقل' : 'Min 6 chars')
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: initBalCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l10n.isAr
                            ? 'الرصيد الافتراضي الابتدائي'
                            : 'Initial Virtual Balance',
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.tr('active')),
                      value: isActive,
                      onChanged: (v) => setState(() => isActive = v),
                    ),
                  ],
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
                      final gov = governorates.firstWhere(
                        (g) => g.id == selectedGovId,
                        orElse: () => governorates.first,
                      );
                      setState(() => busy = true);
                      try {
                        if (existing == null) {
                          await ref
                              .read(authRepositoryProvider)
                              .createDelegateAccount(
                                manager: manager,
                                name: nameCtrl.text,
                                email: emailCtrl.text,
                                password: passCtrl.text,
                                phone: phoneCtrl.text,
                                governorateId: gov.id,
                                governorateName: gov.displayName(l10n.isAr),
                                initialVirtualBalance:
                                    double.tryParse(initBalCtrl.text.trim()) ??
                                        0,
                              );
                        } else {
                          await ref
                              .read(authRepositoryProvider)
                              .updateDelegate(
                                manager: manager,
                                delegate: existing,
                                name: nameCtrl.text,
                                phone: phoneCtrl.text,
                                governorateId: gov.id,
                                governorateName: gov.displayName(l10n.isAr),
                                isActive: isActive,
                              );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                        }
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
}
