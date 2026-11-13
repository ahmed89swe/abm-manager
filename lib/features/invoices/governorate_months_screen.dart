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

/// المستوى الثاني للمدير: عند الضغط على المحافظة تفتح قائمة تحتوي على الأشهر فقط
/// وتعرض رصيد صندوق المحافظة لكل شهر مع إمكانية تعبئة الشهر الحالي أو أي شهر سابق.
class GovernorateMonthsScreen extends ConsumerWidget {
  const GovernorateMonthsScreen({super.key, required this.governorate});

  final Governorate governorate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final invoices = ref.watch(invoicesProvider).value ?? const [];
    final boxes = ref.watch(monthlyBoxesProvider).value ?? const [];
    final govBoxes =
        ref.watch(governorateMonthlyBoxesProvider).value ?? const [];
    final currentMonthKey = ref.watch(currentMonthKeyProvider).value ??
        ServerTimeService.toMonthKey(DateTime.now());

    final govInvoices =
        invoices.where((inv) => inv.governorateId == governorate.id).toList();
    final thisGovSubBoxes =
        govBoxes.where((b) => b.governorateId == governorate.id).toList();

    final monthKeys = <String>{
      currentMonthKey,
      ...boxes.map((b) => b.monthKey),
      ...thisGovSubBoxes.map((b) => b.monthKey),
      ...govInvoices.map((i) => i.invoiceMonthKey),
    }.where((m) => m.isNotEmpty).toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: Text(governorate.displayName(l10n.isAr)),
        actions: [
          IconButton(
            tooltip: l10n.tr('topup_governorate'),
            icon: const Icon(Icons.add_card_rounded),
            onPressed: () => openGovernorateTopUpDialog(
              context: context,
              ref: ref,
              governorate: governorate,
              currentMonthKey: currentMonthKey,
            ),
          ),
        ],
      ),
      body: ResponsivePageContainer(
        maxWidth: 1200,
        child: SingleChildScrollView(
          padding: ResponsiveBreakpoints.pagePadding(context),
          child: ResponsiveCardGrid(
            children: monthKeys.map((monthKey) {
              final parsed = ServerTimeService.parseMonthKey(monthKey);
              final monthInvoices = govInvoices
                  .where((i) => i.invoiceMonthKey == monthKey)
                  .toList();
              final subBox = thisGovSubBoxes.firstWhere(
                (b) => b.monthKey == monthKey,
                orElse: () => GovernorateMonthlyBox.empty(
                  governorateId: governorate.id,
                  governorateName: governorate.displayName(l10n.isAr),
                  monthKey: monthKey,
                ),
              );
              final boxColor = subBox.currentBalance < 0
                  ? AppTheme.dangerColor
                  : AppTheme.successColor;

              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.14),
                    child: Text(
                      '${parsed.month}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
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
                    '${parsed.year} • ${l10n.tr('total_invoices_count')}: ${monthInvoices.length}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            AppFormatters.formatMoney(subBox.currentBalance),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: boxColor,
                            ),
                          ),
                          Text(
                            l10n.tr('manager_gov_box'),
                            style: Theme.of(context).textTheme.labelSmall,
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
                        governorate: governorate,
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
    );
  }
}
