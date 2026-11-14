import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/master_data_models.dart';
import '../../models/monthly_box.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';
import 'manager_boxes_screen.dart';

class MonthlyBoxDetailScreen extends ConsumerWidget {
  const MonthlyBoxDetailScreen({
    super.key,
    required this.monthKey,
    this.governorate,
  });

  final String monthKey;
  final Governorate? governorate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isGovMode = governorate != null;

    final double currentBalance;
    final double totalTopUps;
    final double totalInvDed;
    final double totalExpDed;
    final String title;

    if (isGovMode) {
      final govBoxes =
          ref.watch(governorateMonthlyBoxesProvider).value ?? const [];
      final govBox = govBoxes.firstWhere(
        (b) => b.governorateId == governorate!.id && b.monthKey == monthKey,
        orElse: () => GovernorateMonthlyBox.empty(
          governorateId: governorate!.id,
          governorateName: governorate!.displayName(l10n.isAr),
          monthKey: monthKey,
        ),
      );
      currentBalance = govBox.currentBalance;
      totalTopUps = govBox.totalTopUps;
      totalInvDed = govBox.totalInvoiceDeductions;
      totalExpDed = govBox.totalExpenseDeductions;
      title = '${governorate!.displayName(l10n.isAr)} • ${govBox.label(l10n.isAr)}';
    } else {
      final boxes = ref.watch(monthlyBoxesProvider).value ?? const [];
      final box = boxes.firstWhere(
        (b) => b.monthKey == monthKey,
        orElse: () => MonthlyBox.empty(monthKey),
      );
      currentBalance = box.currentBalance;
      totalTopUps = box.totalCompanyTopUps;
      totalInvDed = box.totalInvoiceDeductions;
      totalExpDed = box.totalExpenseDeductions;
      title = box.label(l10n.isAr);
    }

    final user = ref.watch(currentUserProfileProvider).value;
    final managerId = user?.effectiveManagerId ?? '';
    final txStream = isGovMode
        ? ref
            .watch(boxesRepositoryProvider)
            .watchTransactionsForGovernorateMonth(
              managerId,
              governorate!.id,
              monthKey,
            )
        : ref
            .watch(boxesRepositoryProvider)
            .watchTransactionsForMonth(managerId, monthKey);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: isGovMode
                ? l10n.tr('topup_governorate')
                : l10n.tr('company_topup'),
            icon: const Icon(Icons.add_card_rounded),
            onPressed: () {
              if (isGovMode) {
                openGovernorateTopUpDialog(
                  context: context,
                  ref: ref,
                  governorate: governorate!,
                  initialMonthKey: monthKey,
                );
              } else {
                openCompanyTopUpDialog(
                  context: context,
                  ref: ref,
                  initialMonthKey: monthKey,
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<BoxTransaction>>(
        stream: txStream,
        builder: (context, snapshot) {
          final transactions = snapshot.data ?? const [];
          return ResponsivePageContainer(
            maxWidth: 1200,
            child: ListView(
              padding: ResponsiveBreakpoints.pagePadding(context),
              children: [
                BalanceHeroCard(
                  title: title,
                  subtitle: l10n.tr('current_balance'),
                  balance: currentBalance,
                  currency: l10n.tr('currency'),
                  footerWidgets: [
                    _StatChip(
                      label: isGovMode
                          ? l10n.tr('manager_allocations')
                          : l10n.tr('total_topups'),
                      value: AppFormatters.formatMoney(totalTopUps),
                    ),
                    _StatChip(
                      label: l10n.tr('invoices'),
                      value: AppFormatters.formatMoney(totalInvDed),
                    ),
                    _StatChip(
                      label: l10n.tr('expenses'),
                      value: AppFormatters.formatMoney(totalExpDed),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.isAr
                      ? 'حركات الصندوق والتسديدات في هذا الشهر'
                      : 'Box Transactions & Payments in This Month',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (transactions.isEmpty)
                  EmptyStateWidget(
                    icon: Icons.receipt_long_outlined,
                    message: l10n.tr('no_data'),
                  )
                else
                  ResponsiveCardGrid(
                    maxColumns: 2,
                    twoColumnsBreakpoint: 760,
                    children: transactions.map((tx) {
                      final isCredit = tx.effectiveSignedDelta >= 0;
                      final color =
                          isCredit ? AppTheme.successColor : AppTheme.dangerColor;
                      final sign = isCredit ? '+' : '-';

                      final isCompanyTopUp =
                          tx.type == BoxTransactionType.companyTopUp;
                      final isEditableDelegateTx = tx.type ==
                              BoxTransactionType.delegateVirtualTopUp ||
                          tx.type == BoxTransactionType.delegateVirtualWithdraw;
                      final isDeletableTopUp = (isCompanyTopUp ||
                              tx.type == BoxTransactionType.governorateTopUp ||
                              tx.isDelegateVirtualTx) &&
                          (user?.isManager ?? false);
                      final isEditableCompanyTopUp =
                          isCompanyTopUp && (user?.isManager ?? false);

                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Icon(
                              isCredit
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color: color,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _txTitle(tx, l10n.isAr),
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
                            '${tx.performedByName}${tx.governorateName != null && tx.governorateName!.isNotEmpty ? " • ${tx.governorateName}" : ""}${tx.notes != null && tx.notes!.isNotEmpty ? " • ${tx.notes}" : ""}\n${tx.createdAt != null ? AppFormatters.formatDate(tx.createdAt!, includeTime: true) : ""}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$sign${AppFormatters.formatMoney(tx.amount)}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              if (isEditableCompanyTopUp) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: l10n.tr('edit_company_topup'),
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => openCompanyTopUpDialog(
                                    context: context,
                                    ref: ref,
                                    existingTransaction: tx,
                                  ),
                                ),
                              ] else if (isEditableDelegateTx &&
                                  (user?.isManager ?? false)) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: l10n.tr('edit_delegate_tx'),
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => openEditDelegateBoxTxDialog(
                                    context: context,
                                    ref: ref,
                                    existingTransaction: tx,
                                  ),
                                ),
                              ],
                              if (isDeletableTopUp) ...[
                                IconButton(
                                  tooltip: l10n.tr('delete_topup'),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 20,
                                    color: AppTheme.dangerColor,
                                  ),
                                  onPressed: () =>
                                      confirmAndDeleteTopUpTransaction(
                                    context,
                                    ref,
                                    tx,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onTap: isEditableCompanyTopUp
                              ? () => openCompanyTopUpDialog(
                                    context: context,
                                    ref: ref,
                                    existingTransaction: tx,
                                  )
                              : (isEditableDelegateTx &&
                                      (user?.isManager ?? false))
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
            ),
          );
        },
      ),
    );
  }

  String _txTitle(BoxTransaction tx, bool isAr) {
    switch (tx.type) {
      case BoxTransactionType.companyTopUp:
        return isAr ? 'تعبئة من الشركة' : 'Company Top-Up';
      case BoxTransactionType.governorateTopUp:
        return isAr ? 'تعبئة صندوق المحافظة' : 'Governorate Box Top-Up';
      case BoxTransactionType.delegateVirtualTopUp:
        return isAr ? 'تعبئة مندوب' : 'Delegate Top-Up';
      case BoxTransactionType.delegateVirtualWithdraw:
        return isAr ? 'سحب من صندوق المندوب' : 'Delegate Box Withdrawal';
      case BoxTransactionType.delegateVirtualAdjustment:
        return isAr ? 'تعديل رصيد المندوب' : 'Delegate Balance Adjustment';
      case BoxTransactionType.invoicePayment:
        return isAr ? 'تسديد فاتورة' : 'Invoice Payment';
      case BoxTransactionType.personalExpense:
        return isAr ? 'مصروف شخصي' : 'Personal Expense';
      case BoxTransactionType.invoiceEditAdjustment:
        return isAr ? 'تعديل فاتورة' : 'Invoice Edit Adjustment';
    }
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
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
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
