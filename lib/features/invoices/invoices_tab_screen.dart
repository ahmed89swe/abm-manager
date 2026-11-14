import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/server_time_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/invoice_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import 'create_edit_invoice_screen.dart';
import 'governorate_months_screen.dart';
import 'invoice_card_and_sheet.dart';

class InvoicesTabScreen extends ConsumerWidget {
  const InvoicesTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProfileProvider).value;
    if (user == null) return const SizedBox.shrink();
    return user.isManager
        ? _ManagerGovernoratesView(user: user)
        : _DelegateInvoicesView(user: user);
  }
}

class _ManagerGovernoratesView extends ConsumerStatefulWidget {
  const _ManagerGovernoratesView({required this.user});
  final AppUser user;

  @override
  ConsumerState<_ManagerGovernoratesView> createState() =>
      _ManagerGovernoratesViewState();
}

class _ManagerGovernoratesViewState
    extends ConsumerState<_ManagerGovernoratesView> {
  String _viewMode = 'governorates'; // governorates | all | unpaid | paid
  String? _filterGovId;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final governorates = ref.watch(governoratesProvider).value ?? const [];
    final delegates = ref.watch(delegatesProvider).value ?? const [];
    final invoicesAsync = ref.watch(invoicesProvider);
    final invoices = invoicesAsync.value ?? const [];
    final govBoxes =
        ref.watch(governorateMonthlyBoxesProvider).value ?? const [];

    final totalPaidCount = invoices.where((i) => i.isPaid).length;
    final totalUnpaidCount = invoices.where((i) => !i.isPaid).length;
    final hasSearch = _searchQuery.trim().isNotEmpty;

    var filteredInvoices = invoices;
    if (_viewMode == 'paid') {
      filteredInvoices = filteredInvoices.where((i) => i.isPaid).toList();
    } else if (_viewMode == 'unpaid') {
      filteredInvoices = filteredInvoices.where((i) => !i.isPaid).toList();
    }
    if (_filterGovId != null) {
      filteredInvoices = filteredInvoices
          .where((i) => i.governorateId == _filterGovId)
          .toList();
    }
    if (hasSearch) {
      filteredInvoices = filteredInvoices
          .where((i) => i.matchesSearchQuery(_searchQuery))
          .toList();
    }

    return Scaffold(
      body: ResponsivePageContainer(
        maxWidth: 1240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: InvoiceSearchBar(
                controller: _searchCtrl,
                query: _searchQuery,
                onChanged: (v) => setState(() => _searchQuery = v),
                onClear: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: Text(
                      '${l10n.tr('by_governorates')} (${governorates.length})',
                    ),
                    selected: _viewMode == 'governorates',
                    onSelected: (_) =>
                        setState(() => _viewMode = 'governorates'),
                  ),
                  ChoiceChip(
                    label: Text('${l10n.tr('all')} (${invoices.length})'),
                    selected: _viewMode == 'all',
                    onSelected: (_) => setState(() => _viewMode = 'all'),
                  ),
                  ChoiceChip(
                    label: Text(
                      '${l10n.isAr ? 'على الانتظار / غير مسددة' : 'Pending / Unpaid'} ($totalUnpaidCount)',
                    ),
                    selected: _viewMode == 'unpaid',
                    onSelected: (_) => setState(() => _viewMode = 'unpaid'),
                  ),
                  ChoiceChip(
                    label: Text('${l10n.tr('paid')} ($totalPaidCount)'),
                    selected: _viewMode == 'paid',
                    onSelected: (_) => setState(() => _viewMode = 'paid'),
                  ),
                  if ((_viewMode != 'governorates' || hasSearch) &&
                      governorates.isNotEmpty)
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 160, maxWidth: 230),
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey('inv_tab_gov_$_filterGovId'),
                        initialValue: _filterGovId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.tr('governorate'),
                          isDense: true,
                        ),
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
                        onChanged: (v) => setState(() => _filterGovId = v),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: (_viewMode == 'governorates' && !hasSearch)
                  ? (governorates.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.location_city_outlined,
                          message: l10n.isAr
                              ? 'أضف المحافظات من تبويب المزيد -> الثوابت والمواد للبدء'
                              : 'Add governorates from More -> Master Data to start',
                        )
                      : ListView(
                          padding: ResponsiveBreakpoints.pagePadding(
                            context,
                            withFab: true,
                          ),
                          children: [
                            ResponsiveCardGrid(
                              children: governorates.map((gov) {
                                final govDelegatesCount = delegates
                                    .where((d) => d.governorateId == gov.id)
                                    .length;
                                final govInvoices = invoices
                                    .where(
                                        (inv) => inv.governorateId == gov.id)
                                    .toList();
                                final paidCount = govInvoices
                                    .where((inv) => inv.isPaid)
                                    .length;
                                final unpaidCount = govInvoices
                                    .where((inv) => !inv.isPaid)
                                    .length;
                                final govBoxBalance = govBoxes
                                    .where((b) => b.governorateId == gov.id)
                                    .fold<double>(0.0,
                                        (acc, b) => acc + b.currentBalance);
                                final balColor = govBoxBalance < 0
                                    ? AppTheme.dangerColor
                                    : AppTheme.successColor;

                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            GovernorateMonthsScreen(
                                          governorate: gov,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 22,
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(
                                                            alpha: 0.12),
                                                child: Icon(
                                                  Icons.location_city_rounded,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      gov.displayName(
                                                          l10n.isAr),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 17,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${l10n.tr('delegates')}: $govDelegatesCount • ${l10n.tr('invoices')}: ${govInvoices.length}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(
                                                  Icons.chevron_right_rounded),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            alignment:
                                                WrapAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  StatusBadge(
                                                    label:
                                                        '${l10n.tr('paid')}: $paidCount',
                                                    color:
                                                        AppTheme.successColor,
                                                  ),
                                                  StatusBadge(
                                                    label:
                                                        '${l10n.tr('pending_payment')}: $unpaidCount',
                                                    color: unpaidCount > 0
                                                        ? AppTheme.warningColor
                                                        : AppTheme.successColor,
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                AppFormatters.formatMoney(
                                                  govBoxBalance,
                                                  currency:
                                                      l10n.tr('currency'),
                                                ),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                  color: balColor,
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
                        ))
                  : invoicesAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, _) => EmptyStateWidget(
                        icon: Icons.error_outline,
                        message: '$err',
                      ),
                      data: (_) {
                        if (filteredInvoices.isEmpty) {
                          return EmptyStateWidget(
                            icon: Icons.receipt_long_outlined,
                            message: l10n.tr('no_data'),
                          );
                        }
                        return SingleChildScrollView(
                          padding: ResponsiveBreakpoints.pagePadding(
                            context,
                            withFab: true,
                          ),
                          child: ResponsiveCardGrid(
                            maxColumns: 2,
                            twoColumnsBreakpoint: 720,
                            children: filteredInvoices
                                .map(
                                  (inv) => InvoiceCard(
                                    invoice: inv,
                                    user: widget.user,
                                    onTap: () => showInvoiceDetailsSheet(
                                      context,
                                      ref,
                                      inv,
                                      widget.user,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateEditInvoiceScreen()),
        ),
        icon: const Icon(Icons.post_add_rounded),
        label: Text(l10n.tr('add_invoice')),
      ),
    );
  }
}

class _DelegateInvoicesView extends ConsumerStatefulWidget {
  const _DelegateInvoicesView({required this.user});
  final AppUser user;

  @override
  ConsumerState<_DelegateInvoicesView> createState() =>
      _DelegateInvoicesViewState();
}

class _DelegateInvoicesViewState extends ConsumerState<_DelegateInvoicesView> {
  String _statusFilter = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _resolveMonthKey(InvoiceModel inv) =>
      inv.effectiveMonthKey.isNotEmpty
          ? inv.effectiveMonthKey
          : inv.invoiceDateMonthKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final invoicesAsync = ref.watch(invoicesProvider);
    final currentMonthKey = ref.watch(currentMonthKeyProvider).value ??
        ServerTimeService.toMonthKey(DateTime.now());
    final hasSearch = _searchQuery.trim().isNotEmpty;

    return Scaffold(
      body: ResponsivePageContainer(
        maxWidth: 1240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: InvoiceSearchBar(
                controller: _searchCtrl,
                query: _searchQuery,
                onChanged: (v) => setState(() => _searchQuery = v),
                onClear: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  FilterChip(
                    label: Text(l10n.tr('all')),
                    selected: _statusFilter == 'all',
                    onSelected: (_) => setState(() => _statusFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(l10n.tr('unpaid')),
                    selected: _statusFilter == 'unpaid',
                    onSelected: (_) =>
                        setState(() => _statusFilter = 'unpaid'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(l10n.tr('paid')),
                    selected: _statusFilter == 'paid',
                    onSelected: (_) => setState(() => _statusFilter = 'paid'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: (invoicesAsync.isLoading && !invoicesAsync.hasValue)
                  ? const Center(child: CircularProgressIndicator())
                  : (invoicesAsync.hasError && !invoicesAsync.hasValue)
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 48,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '${invoicesAsync.error}',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: () =>
                                      ref.invalidate(invoicesProvider),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(
                                    l10n.isAr ? 'إعادة المحاولة' : 'Retry',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : () {
                          final allInvoices =
                              invoicesAsync.value ?? const <InvoiceModel>[];
                          var filtered = allInvoices;
                          if (_statusFilter == 'paid') {
                            filtered =
                                filtered.where((i) => i.isPaid).toList();
                          } else if (_statusFilter == 'unpaid') {
                            filtered =
                                filtered.where((i) => !i.isPaid).toList();
                          }

                          if (hasSearch) {
                            final searched = filtered
                                .where((i) => i.matchesSearchQuery(_searchQuery))
                                .toList();
                            if (searched.isEmpty) {
                              return EmptyStateWidget(
                                icon: Icons.search_off_rounded,
                                message: l10n.tr('no_search_results'),
                              );
                            }
                            return _buildInvoicesGrid(
                              context,
                              ref,
                              searched,
                              widget.user,
                            );
                          }

                          final monthSet = <String>{
                            if (_statusFilter == 'all') currentMonthKey,
                            ...filtered.map(_resolveMonthKey),
                          }.where((m) => m.isNotEmpty).toList()
                            ..sort((a, b) => b.compareTo(a));

                          if (monthSet.isEmpty) {
                            return EmptyStateWidget(
                              icon: Icons.receipt_long_outlined,
                              message: l10n.tr('no_data'),
                            );
                          }

                          return SingleChildScrollView(
                            padding: ResponsiveBreakpoints.pagePadding(
                              context,
                              withFab: true,
                            ),
                            child: ResponsiveCardGrid(
                              children: monthSet.map((monthKey) {
                                final parsed =
                                    ServerTimeService.parseMonthKey(monthKey);
                                final monthAll = allInvoices
                                    .where((i) => _resolveMonthKey(i) == monthKey)
                                    .toList();
                                final monthVisible = filtered
                                    .where((i) => _resolveMonthKey(i) == monthKey)
                                    .toList();
                                final paidCount =
                                    monthAll.where((i) => i.isPaid).length;
                                final unpaidCount =
                                    monthAll.where((i) => !i.isPaid).length;
                                final totalSum = monthVisible.fold<double>(
                                  0.0,
                                  (acc, inv) => acc + inv.totalAmount,
                                );

                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.14),
                                      child: Text(
                                        '${parsed.month}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      l10n.monthName(parsed.month),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${parsed.year} • ${l10n.tr('total_invoices_count')}: ${monthAll.length} (${l10n.tr('paid')}: $paidCount • ${l10n.tr('pending_payment')}: $unpaidCount)',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          AppFormatters.formatMoney(totalSum),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(Icons.chevron_right_rounded),
                                      ],
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            DelegateMonthInvoicesScreen(
                                          monthKey: monthKey,
                                          initialStatusFilter: _statusFilter,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateEditInvoiceScreen()),
        ),
        icon: const Icon(Icons.post_add_rounded),
        label: Text(l10n.tr('add_invoice')),
      ),
    );
  }
}

/// شاشة فواتير المندوب داخل شهر محدد مع بحث وفلترة بالحالة
class DelegateMonthInvoicesScreen extends ConsumerStatefulWidget {
  const DelegateMonthInvoicesScreen({
    super.key,
    required this.monthKey,
    this.initialStatusFilter = 'all',
  });

  final String monthKey;
  final String initialStatusFilter;

  @override
  ConsumerState<DelegateMonthInvoicesScreen> createState() =>
      _DelegateMonthInvoicesScreenState();
}

class _DelegateMonthInvoicesScreenState
    extends ConsumerState<DelegateMonthInvoicesScreen> {
  late String _statusFilter = widget.initialStatusFilter;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProfileProvider).value;
    if (user == null) return const SizedBox.shrink();

    final allInvoices = ref.watch(invoicesProvider).value ?? const <InvoiceModel>[];
    final monthInvoices = allInvoices.where((inv) {
      final m = inv.effectiveMonthKey.isNotEmpty
          ? inv.effectiveMonthKey
          : inv.invoiceDateMonthKey;
      return m == widget.monthKey;
    }).toList();

    final paidCount = monthInvoices.where((i) => i.isPaid).length;
    final unpaidCount = monthInvoices.where((i) => !i.isPaid).length;

    final filtered = monthInvoices.where((inv) {
      if (_statusFilter == 'paid' && !inv.isPaid) return false;
      if (_statusFilter == 'unpaid' && inv.isPaid) return false;
      if (_searchQuery.trim().isNotEmpty &&
          !inv.matchesSearchQuery(_searchQuery)) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppFormatters.formatMonthLabel(widget.monthKey, isAr: l10n.isAr),
        ),
      ),
      body: ResponsivePageContainer(
        maxWidth: 1240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: InvoiceSearchBar(
                controller: _searchCtrl,
                query: _searchQuery,
                onChanged: (v) => setState(() => _searchQuery = v),
                onClear: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  FilterChip(
                    label: Text('${l10n.tr('all')} (${monthInvoices.length})'),
                    selected: _statusFilter == 'all',
                    onSelected: (_) => setState(() => _statusFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text('${l10n.tr('unpaid')} ($unpaidCount)'),
                    selected: _statusFilter == 'unpaid',
                    onSelected: (_) =>
                        setState(() => _statusFilter = 'unpaid'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text('${l10n.tr('paid')} ($paidCount)'),
                    selected: _statusFilter == 'paid',
                    onSelected: (_) => setState(() => _statusFilter = 'paid'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? EmptyStateWidget(
                      icon: _searchQuery.trim().isNotEmpty
                          ? Icons.search_off_rounded
                          : Icons.receipt_long_outlined,
                      message: _searchQuery.trim().isNotEmpty
                          ? l10n.tr('no_search_results')
                          : l10n.tr('no_data'),
                    )
                  : _buildInvoicesGrid(context, ref, filtered, user),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateEditInvoiceScreen()),
        ),
        icon: const Icon(Icons.post_add_rounded),
        label: Text(l10n.tr('add_invoice')),
      ),
    );
  }
}

Widget _buildInvoicesGrid(
  BuildContext context,
  WidgetRef ref,
  List<InvoiceModel> invoices,
  AppUser user,
) {
  return SingleChildScrollView(
    padding: ResponsiveBreakpoints.pagePadding(context, withFab: true),
    child: ResponsiveCardGrid(
      maxColumns: 2,
      twoColumnsBreakpoint: 720,
      children: invoices
          .map(
            (inv) => InvoiceCard(
              invoice: inv,
              user: user,
              onTap: () => showInvoiceDetailsSheet(context, ref, inv, user),
            ),
          )
          .toList(),
    ),
  );
}
