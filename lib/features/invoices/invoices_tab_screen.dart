import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
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

class _ManagerGovernoratesView extends ConsumerWidget {
  const _ManagerGovernoratesView({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final governorates = ref.watch(governoratesProvider).value ?? const [];
    final delegates = ref.watch(delegatesProvider).value ?? const [];
    final invoices = ref.watch(invoicesProvider).value ?? const [];
    final govBoxes =
        ref.watch(governorateMonthlyBoxesProvider).value ?? const [];

    return Scaffold(
      body: governorates.isEmpty
          ? EmptyStateWidget(
              icon: Icons.location_city_outlined,
              message: l10n.isAr
                  ? 'أضف المحافظات من تبويب المزيد -> الثوابت والمواد للبدء'
                  : 'Add governorates from More -> Master Data to start',
            )
          : ResponsivePageContainer(
              maxWidth: 1240,
              child: ListView(
                padding:
                    ResponsiveBreakpoints.pagePadding(context, withFab: true),
                children: [
                  ResponsiveCardGrid(
                    children: governorates.map((gov) {
                      final govDelegatesCount = delegates
                          .where((d) => d.governorateId == gov.id)
                          .length;
                      final govInvoices = invoices
                          .where((inv) => inv.governorateId == gov.id)
                          .toList();
                      final unpaidCount =
                          govInvoices.where((inv) => !inv.isPaid).length;
                      final govBoxBalance = govBoxes
                          .where((b) => b.governorateId == gov.id)
                          .fold<double>(
                              0.0, (acc, b) => acc + b.currentBalance);
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
                                  GovernorateMonthsScreen(governorate: gov),
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
                                      radius: 22,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.12),
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
                                            gov.displayName(l10n.isAr),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
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
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    StatusBadge(
                                      label:
                                          '${l10n.tr('unpaid')}: $unpaidCount',
                                      color: unpaidCount > 0
                                          ? AppTheme.warningColor
                                          : AppTheme.successColor,
                                    ),
                                    Flexible(
                                      child: Text(
                                        AppFormatters.formatMoney(
                                          govBoxBalance,
                                          currency: l10n.tr('currency'),
                                        ),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: balColor,
                                        ),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final invoicesAsync = ref.watch(invoicesProvider);

    return Scaffold(
      body: ResponsivePageContainer(
        maxWidth: 1240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
              child: invoicesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, _) => EmptyStateWidget(
                  icon: Icons.error_outline,
                  message: '$err',
                ),
                data: (rawList) {
                  var invoices = rawList;
                  if (_statusFilter == 'paid') {
                    invoices = invoices.where((i) => i.isPaid).toList();
                  } else if (_statusFilter == 'unpaid') {
                    invoices = invoices.where((i) => !i.isPaid).toList();
                  }

                  if (invoices.isEmpty) {
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
                      children: invoices
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
