import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/server_time_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/master_data_models.dart';
import '../../models/monthly_box.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import '../boxes/manager_boxes_screen.dart';
import 'governorate_month_detail_screen.dart';
import 'invoice_card_and_sheet.dart';

/// المستوى الثاني للمدير: عند الضغط على المحافظة تفتح قائمة تحتوي على الأشهر فقط
/// وتعرض رصيد صندوق المحافظة لكل شهر مع إمكانية تعبئة الشهر الحالي أو أي شهر سابق والبحث في فواتير المحافظة.
class GovernorateMonthsScreen extends ConsumerStatefulWidget {
  const GovernorateMonthsScreen({super.key, required this.governorate});

  final Governorate governorate;

  @override
  ConsumerState<GovernorateMonthsScreen> createState() =>
      _GovernorateMonthsScreenState();
}

class _GovernorateMonthsScreenState
    extends ConsumerState<GovernorateMonthsScreen> {
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
    final invoices = ref.watch(invoicesProvider).value ?? const [];
    final boxes = ref.watch(monthlyBoxesProvider).value ?? const [];
    final govBoxes =
        ref.watch(governorateMonthlyBoxesProvider).value ?? const [];
    final currentMonthKey = ref.watch(currentMonthKeyProvider).value ??
        ServerTimeService.toMonthKey(DateTime.now());

    final govInvoices = invoices
        .where((inv) => inv.governorateId == widget.governorate.id)
        .toList();
    final thisGovSubBoxes =
        govBoxes.where((b) => b.governorateId == widget.governorate.id).toList();

    final monthKeys = <String>{
      currentMonthKey,
      ...boxes.map((b) => b.monthKey),
      ...thisGovSubBoxes.map((b) => b.monthKey),
      ...govInvoices.map((i) => i.invoiceMonthKey),
      ...govInvoices.map((i) => i.effectiveMonthKey),
    }.where((m) => m.isNotEmpty).toList()
      ..sort((a, b) => b.compareTo(a));

    final hasSearch = _searchQuery.trim().isNotEmpty;
    final searchedInvoices = hasSearch
        ? govInvoices
            .where((i) => i.matchesSearchQuery(_searchQuery))
            .toList()
        : const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.governorate.displayName(l10n.isAr)),
        actions: [
          IconButton(
            tooltip: l10n.tr('topup_governorate'),
            icon: const Icon(Icons.add_card_rounded),
            onPressed: () => openGovernorateTopUpDialog(
              context: context,
              ref: ref,
              governorate: widget.governorate,
              currentMonthKey: currentMonthKey,
            ),
          ),
        ],
      ),
      body: ResponsivePageContainer(
        maxWidth: 1200,
        child: Column(
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
            Expanded(
              child: hasSearch
                  ? (searchedInvoices.isEmpty || user == null
                      ? EmptyStateWidget(
                          icon: Icons.search_off_rounded,
                          message: l10n.tr('no_search_results'),
                        )
                      : SingleChildScrollView(
                          padding: ResponsiveBreakpoints.pagePadding(context),
                          child: ResponsiveCardGrid(
                            maxColumns: 2,
                            twoColumnsBreakpoint: 720,
                            children: searchedInvoices
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
                        ))
                  : SingleChildScrollView(
                      padding: ResponsiveBreakpoints.pagePadding(context),
                      child: ResponsiveCardGrid(
                        children: monthKeys.map((monthKey) {
                          final parsed =
                              ServerTimeService.parseMonthKey(monthKey);
                          final monthInvoices = govInvoices
                              .where((i) => i.effectiveMonthKey == monthKey)
                              .toList();
                          final paidCount =
                              monthInvoices.where((i) => i.isPaid).length;
                          final unpaidCount =
                              monthInvoices.where((i) => !i.isPaid).length;
                          final subBox = thisGovSubBoxes.firstWhere(
                            (b) => b.monthKey == monthKey,
                            orElse: () => GovernorateMonthlyBox.empty(
                              governorateId: widget.governorate.id,
                              governorateName:
                                  widget.governorate.displayName(l10n.isAr),
                              monthKey: monthKey,
                            ),
                          );
                          final boxColor = subBox.currentBalance < 0
                              ? AppTheme.dangerColor
                              : AppTheme.successColor;

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
                                    color:
                                        Theme.of(context).colorScheme.primary,
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
                                '${parsed.year} • ${l10n.tr('total_invoices_count')}: ${monthInvoices.length} (${l10n.tr('paid')}: $paidCount • ${l10n.tr('pending_payment')}: $unpaidCount)',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        AppFormatters.formatMoney(
                                          subBox.currentBalance,
                                        ),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: boxColor,
                                        ),
                                      ),
                                      Text(
                                        l10n.tr('manager_gov_box'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GovernorateMonthDetailScreen(
                                    governorate: widget.governorate,
                                    monthKey: monthKey,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
