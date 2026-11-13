import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/server_time_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/master_data_models.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/month_year_picker.dart';
import '../../widgets/user_avatar_widget.dart';

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
                                  label: Text(l10n.tr('topup_delegate')),
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
