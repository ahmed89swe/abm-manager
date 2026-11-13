import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/invoice_model.dart';
import '../../models/master_data_models.dart';
import '../../models/monthly_box.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../boxes/manager_boxes_screen.dart';
import 'create_edit_invoice_screen.dart';
import 'invoice_card_and_sheet.dart';

/// شاشة تفاصيل الشهر داخل المحافظة للمدير:
/// تعرض صندوق المحافظة الفرعي للشهر + صناديق المندوبين + قوائم الفواتير لكل مندوب في هذا الشهر.
class GovernorateMonthDetailScreen extends ConsumerStatefulWidget {
  const GovernorateMonthDetailScreen({
    super.key,
    required this.governorate,
    required this.monthKey,
  });

  final Governorate governorate;
  final String monthKey;

  @override
  ConsumerState<GovernorateMonthDetailScreen> createState() =>
      _GovernorateMonthDetailScreenState();
}

class _GovernorateMonthDetailScreenState
    extends ConsumerState<GovernorateMonthDetailScreen> {
  String _selectedGroupFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProfileProvider).value;
    if (user == null) return const SizedBox.shrink();

    final allInvoices = ref.watch(invoicesProvider).value ?? const [];
    final allDelegates = ref.watch(delegatesProvider).value ?? const [];
    final allGovBoxes =
        ref.watch(governorateMonthlyBoxesProvider).value ?? const [];

    final govSubBox = allGovBoxes.firstWhere(
      (b) =>
          b.governorateId == widget.governorate.id &&
          b.monthKey == widget.monthKey,
      orElse: () => GovernorateMonthlyBox.empty(
        governorateId: widget.governorate.id,
        governorateName: widget.governorate.displayName(l10n.isAr),
        monthKey: widget.monthKey,
      ),
    );

    final govDelegates = allDelegates
        .where((d) => d.governorateId == widget.governorate.id)
        .toList();

    final monthInvoices = allInvoices
        .where(
          (inv) =>
              inv.governorateId == widget.governorate.id &&
              inv.invoiceMonthKey == widget.monthKey,
        )
        .toList();

    // تجميع الفواتير حسب المندوب أو فواتير المدير/المشتركة
    final Map<String, List<InvoiceModel>> grouped = {};
    for (final d in govDelegates) {
      grouped[d.uid] = [];
    }
    final List<InvoiceModel> managerOrSharedInvoices = [];

    for (final inv in monthInvoices) {
      if (inv.assignmentType == InvoiceAssignmentType.specificDelegate &&
          inv.assignedDelegateId != null &&
          grouped.containsKey(inv.assignedDelegateId)) {
        grouped[inv.assignedDelegateId!]!.add(inv);
      } else if (inv.paidByRole == 'delegate' &&
          inv.paidByUid != null &&
          grouped.containsKey(inv.paidByUid)) {
        grouped[inv.paidByUid!]!.add(inv);
      } else {
        managerOrSharedInvoices.add(inv);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.governorate.displayName(l10n.isAr)} • ${AppFormatters.formatMonthLabel(widget.monthKey, isAr: l10n.isAr)}',
        ),
        actions: [
          IconButton(
            tooltip: l10n.tr('topup_governorate'),
            icon: const Icon(Icons.add_card_rounded),
            onPressed: () => openGovernorateTopUpDialog(
              context: context,
              ref: ref,
              governorate: widget.governorate,
              initialMonthKey: widget.monthKey,
            ),
          ),
        ],
      ),
      body: ResponsivePageContainer(
        maxWidth: 1240,
        child: ListView(
          padding: ResponsiveBreakpoints.pagePadding(context, withFab: true),
          children: [
            // شريط الصناديق: صندوق المدير الفرعي في المحافظة + صناديق المندوبين
            Text(
              '${l10n.tr('manager_gov_box')} & ${l10n.tr('delegate_boxes')}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 124,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _MiniBoxCard(
                    title: l10n.tr('manager_gov_box'),
                    subtitle:
                        '${l10n.tr('manager_allocations')}: ${AppFormatters.formatMoney(govSubBox.totalTopUps)}',
                    amount: govSubBox.currentBalance,
                    currency: l10n.tr('currency'),
                    color: govSubBox.currentBalance < 0
                        ? AppTheme.dangerColor
                        : Theme.of(context).colorScheme.secondary,
                    icon: Icons.account_balance_outlined,
                  ),
                  ...govDelegates.map(
                    (d) => _MiniBoxCard(
                      title: d.name,
                      subtitle: l10n.isAr
                          ? 'الصندوق الافتراضي للمندوب'
                          : 'Delegate Virtual Box',
                      amount: d.virtualBoxBalance,
                      currency: l10n.tr('currency'),
                      color: d.virtualBoxBalance < 0
                          ? AppTheme.dangerColor
                          : Theme.of(context).colorScheme.primary,
                      icon: Icons.badge_outlined,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // فلتر سريع حسب المندوب
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: Text(l10n.tr('all')),
                    selected: _selectedGroupFilter == 'all',
                    onSelected: (_) =>
                        setState(() => _selectedGroupFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  ...govDelegates.map(
                    (d) => Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: FilterChip(
                        label:
                            Text('${d.name} (${grouped[d.uid]?.length ?? 0})'),
                        selected: _selectedGroupFilter == d.uid,
                        onSelected: (_) =>
                            setState(() => _selectedGroupFilter = d.uid),
                      ),
                    ),
                  ),
                  if (managerOrSharedInvoices.isNotEmpty)
                    FilterChip(
                      label: Text(
                        '${l10n.isAr ? "المدير / عام المحافظة" : "Manager / Shared"} (${managerOrSharedInvoices.length})',
                      ),
                      selected: _selectedGroupFilter == 'shared',
                      onSelected: (_) =>
                          setState(() => _selectedGroupFilter = 'shared'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (monthInvoices.isEmpty)
              EmptyStateWidget(
                icon: Icons.receipt_long_outlined,
                message: l10n.tr('no_data'),
              )
            else ...[
              if (_selectedGroupFilter == 'all' ||
                  _selectedGroupFilter == 'shared') ...[
                if (managerOrSharedInvoices.isNotEmpty) ...[
                  _GroupHeader(
                    title: l10n.isAr
                        ? 'فواتير المدير / مشتركة لجميع مندوبي المحافظة'
                        : 'Manager & Governorate Shared Invoices',
                    count: managerOrSharedInvoices.length,
                  ),
                  ResponsiveCardGrid(
                    maxColumns: 2,
                    twoColumnsBreakpoint: 720,
                    children: managerOrSharedInvoices
                        .map(
                          (inv) => InvoiceCard(
                            invoice: inv,
                            user: user,
                            onTap: () => showInvoiceDetailsSheet(
                              context,
                              ref,
                              inv,
                              user,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
              ...govDelegates.where((d) {
                return _selectedGroupFilter == 'all' ||
                    _selectedGroupFilter == d.uid;
              }).map((d) {
                final list = grouped[d.uid] ?? const [];
                if (list.isEmpty && _selectedGroupFilter == 'all') {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GroupHeader(title: d.name, count: list.length),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          l10n.tr('no_data'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    else
                      ResponsiveCardGrid(
                        maxColumns: 2,
                        twoColumnsBreakpoint: 720,
                        children: list
                            .map(
                              (inv) => InvoiceCard(
                                invoice: inv,
                                user: user,
                                onTap: () => showInvoiceDetailsSheet(
                                  context,
                                  ref,
                                  inv,
                                  user,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 12),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateEditInvoiceScreen(
              initialGovernorateId: widget.governorate.id,
            ),
          ),
        ),
        icon: const Icon(Icons.add),
        label: Text(l10n.tr('add_invoice')),
      ),
    );
  }
}

class _MiniBoxCard extends StatelessWidget {
  const _MiniBoxCard({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
    required this.color,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final double amount;
  final String currency;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 225,
      margin: const EdgeInsetsDirectional.only(end: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              AppFormatters.formatMoney(amount, currency: currency),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 11,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
