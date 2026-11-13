import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/server_time_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/personal_expense_model.dart';
import '../../providers/app_providers.dart';
import '../../services/receipt_storage_service.dart';
import '../../widgets/common_widgets.dart';

class PersonalExpensesScreen extends ConsumerStatefulWidget {
  const PersonalExpensesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<PersonalExpensesScreen> createState() =>
      _PersonalExpensesScreenState();
}

class _PersonalExpensesScreenState
    extends ConsumerState<PersonalExpensesScreen> {
  String? _filterUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProfileProvider).value;
    if (user == null) return const SizedBox.shrink();

    final expensesAsync = ref.watch(personalExpensesProvider);
    final delegates = ref.watch(delegatesProvider).value ?? const [];
    final governorates = ref.watch(governoratesProvider).value ?? const [];
    var expenses = expensesAsync.value ?? const [];

    if (user.isManager && _filterUserId != null) {
      expenses = expenses.where((e) => e.userId == _filterUserId).toList();
    }

    final totalExpenses =
        expenses.fold<double>(0.0, (acc, e) => acc + e.amount);

    return Scaffold(
      appBar: (!widget.embedded && user.isManager)
          ? AppBar(title: Text(l10n.tr('expenses')))
          : null,
      body: ResponsivePageContainer(
        maxWidth: 1200,
        child: ListView(
          padding: ResponsiveBreakpoints.pagePadding(context, withFab: true),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(
                    alpha: 0.45,
                  ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 14,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.wallet_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.tr('personal_expenses_total'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                AppFormatters.formatMoney(
                                  totalExpenses,
                                  currency: l10n.tr('currency'),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (user.isManager && delegates.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 180,
                              maxWidth: 260,
                            ),
                            child: DropdownButtonFormField<String?>(
                              key: ValueKey('exp_filter_$_filterUserId'),
                              initialValue: _filterUserId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: l10n.tr('filter'),
                                isDense: true,
                              ),
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(l10n.tr('all')),
                                ),
                                DropdownMenuItem<String?>(
                                  value: user.uid,
                                  child: Text(user.name),
                                ),
                                ...delegates.map(
                                  (d) => DropdownMenuItem<String?>(
                                    value: d.uid,
                                    child: Text(d.name),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _filterUserId = v),
                            ),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: () => _openExpenseDialog(user),
                          icon: const Icon(Icons.add),
                          label: Text(l10n.tr('add_personal_expense')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (expensesAsync.isLoading && expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (expenses.isEmpty)
              EmptyStateWidget(
                icon: Icons.wallet_outlined,
                message: l10n.tr('no_data'),
              )
            else
              ResponsiveCardGrid(
                maxColumns: 2,
                twoColumnsBreakpoint: 720,
                children: expenses.map((exp) {
                  final canEdit = user.isManager || exp.userId == user.uid;
                  final deductMonth =
                      (exp.deductedManagerMonthKey ?? '').isNotEmpty
                          ? exp.deductedManagerMonthKey!
                          : exp.monthKey;
                  final govName = (exp.governorateName ?? '').isNotEmpty
                      ? exp.governorateName!
                      : governorates
                          .where((g) => g.id == exp.governorateId)
                          .map((g) => g.displayName(l10n.isAr))
                          .firstOrNull;
                  return Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.dangerColor
                                    .withValues(alpha: 0.12),
                                child: const Icon(
                                  Icons.receipt_outlined,
                                  color: AppTheme.dangerColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          exp.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        if (exp.isEdited)
                                          StatusBadge(
                                            label: l10n.tr('edited_label'),
                                            color: AppTheme.warningColor,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${exp.userName} • ${AppFormatters.formatDate(exp.expenseDate)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (deductMonth.isNotEmpty)
                                          AppFormatters.formatMonthLabel(
                                            deductMonth,
                                            isAr: l10n.isAr,
                                          ),
                                        if (govName != null &&
                                            govName.isNotEmpty)
                                          govName,
                                      ].join(' • '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    if ((exp.notes ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        exp.notes!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '-${AppFormatters.formatMoney(exp.amount)}',
                                style: const TextStyle(
                                  color: AppTheme.dangerColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          if ((exp.receiptImageUrl ?? '').isNotEmpty ||
                              canEdit ||
                              user.isManager) ...[
                            const SizedBox(height: 6),
                            const Divider(height: 1),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if ((exp.receiptImageUrl ?? '').isNotEmpty)
                                  IconButton(
                                    tooltip: l10n.tr('view_receipt'),
                                    icon: const Icon(Icons.image_outlined,
                                        size: 20),
                                    onPressed: () => showReceiptImageDialog(
                                      context,
                                      exp.receiptImageUrl!,
                                    ),
                                  ),
                                if (canEdit)
                                  IconButton(
                                    tooltip: l10n.tr('edit_personal_expense'),
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 20),
                                    onPressed: () => _openExpenseDialog(
                                      user,
                                      existing: exp,
                                    ),
                                  ),
                                if (user.isManager)
                                  IconButton(
                                    tooltip: l10n.tr('delete_personal_expense'),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: AppTheme.dangerColor,
                                    ),
                                    onPressed: () =>
                                        _confirmDeleteExpense(user, exp),
                                  ),
                              ],
                            ),
                          ],
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
        onPressed: () => _openExpenseDialog(user),
        icon: const Icon(Icons.add),
        label: Text(l10n.tr('add_personal_expense')),
      ),
    );
  }

  Future<void> _confirmDeleteExpense(
    AppUser user,
    PersonalExpenseModel exp,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('delete_personal_expense')),
        content: Text(l10n.tr('delete_expense_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(expensesRepositoryProvider).deletePersonalExpense(
            actor: user,
            expense: exp,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  void _openExpenseDialog(
    AppUser user, {
    PersonalExpenseModel? existing,
  }) {
    final l10n = AppLocalizations.of(context);
    final isEdit = existing != null;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amountCtrl = TextEditingController(
      text: existing != null
          ? (existing.amount.truncateToDouble() == existing.amount
              ? existing.amount.toStringAsFixed(0)
              : existing.amount.toStringAsFixed(2))
          : '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final formKey = GlobalKey<FormState>();

    final now = DateTime.now();
    final boxes = user.isManager
        ? (ref.read(monthlyBoxesProvider).value ?? const [])
        : const [];
    final governorates = user.isManager
        ? (ref.read(governoratesProvider).value ?? const [])
        : const [];

    final initialMonth =
        (existing?.deductedManagerMonthKey ?? '').isNotEmpty
            ? existing!.deductedManagerMonthKey!
            : (existing != null && existing.monthKey.isNotEmpty
                ? existing.monthKey
                : ServerTimeService.toMonthKey(now));

    final monthOptions = <String>{
      initialMonth,
      ...boxes.map((b) => b.monthKey),
      for (int i = 0; i < 12; i++)
        ServerTimeService.toMonthKey(DateTime(now.year, now.month - i, 1)),
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    String selectedMonth = initialMonth;
    DateTime selectedDate = existing?.expenseDate ?? now;
    String? selectedGovId = (existing?.governorateId ?? '').isNotEmpty
        ? existing!.governorateId
        : null;
    final knownGovIds = governorates.map((g) => g.id).toSet();
    if (selectedGovId != null && !knownGovIds.contains(selectedGovId)) {
      selectedGovId = null;
    }

    PickedImageData? receiptImage;
    bool removeExistingReceipt = false;
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            isEdit
                ? l10n.tr('edit_personal_expense')
                : l10n.tr('add_personal_expense'),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320, maxWidth: 460),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.tr('expense_title'),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? l10n.tr('required_field')
                          : null,
                    ),
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 10),
                    if (user.isManager) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.tr('invoice_date')),
                        subtitle:
                            Text(AppFormatters.formatDate(selectedDate)),
                        trailing: TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime(2023),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setState(() {
                                selectedDate = picked;
                                selectedMonth =
                                    ServerTimeService.toMonthKey(picked);
                                if (!monthOptions.contains(selectedMonth)) {
                                  monthOptions.add(selectedMonth);
                                  monthOptions.sort((a, b) => b.compareTo(a));
                                }
                              });
                            }
                          },
                          child: Text(l10n.isAr ? 'تغيير' : 'Change'),
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('expense_month_$selectedMonth'),
                        initialValue: selectedMonth,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.tr('select_deduct_month'),
                        ),
                        items: monthOptions
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                  AppFormatters.formatMonthLabel(
                                    m,
                                    isAr: l10n.isAr,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => selectedMonth = v);
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        key: ValueKey('expense_gov_$selectedGovId'),
                        initialValue: selectedGovId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.tr('governorate'),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(l10n.tr('general_expense_no_gov')),
                          ),
                          ...governorates.map(
                            (g) => DropdownMenuItem<String?>(
                              value: g.id,
                              child: Text(g.displayName(l10n.isAr)),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => selectedGovId = v),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextFormField(
                      controller: notesCtrl,
                      decoration: InputDecoration(labelText: l10n.tr('notes')),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (!kIsWeb) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final f = await ReceiptStorageService.instance
                                    .pickImage(source: ImageSource.camera);
                                if (f != null) {
                                  setState(() {
                                    receiptImage = f;
                                    removeExistingReceipt = false;
                                  });
                                }
                              },
                              icon: const Icon(Icons.camera_alt_outlined,
                                  size: 18),
                              label: Text(l10n.tr('camera')),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final f = await ReceiptStorageService.instance
                                  .pickImage(source: ImageSource.gallery);
                              if (f != null) {
                                setState(() {
                                  receiptImage = f;
                                  removeExistingReceipt = false;
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library_outlined,
                                size: 18),
                            label: Text(l10n.tr('gallery')),
                          ),
                        ),
                      ],
                    ),
                    if (receiptImage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            receiptImage!.bytes,
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    else if (isEdit &&
                        (existing.receiptImageUrl ?? '').isNotEmpty &&
                        !removeExistingReceipt)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: () => showReceiptImageDialog(
                                ctx,
                                existing.receiptImageUrl!,
                              ),
                              icon: const Icon(Icons.image_outlined, size: 18),
                              label: Text(l10n.tr('view_receipt')),
                            ),
                            TextButton.icon(
                              onPressed: () => setState(
                                  () => removeExistingReceipt = true),
                              icon: const Icon(
                                Icons.close,
                                size: 18,
                                color: AppTheme.dangerColor,
                              ),
                              label: Text(
                                l10n.tr('delete'),
                                style: const TextStyle(
                                  color: AppTheme.dangerColor,
                                ),
                              ),
                            ),
                          ],
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
                      setState(() => busy = true);
                      final selectedGovName = selectedGovId == null
                          ? null
                          : governorates
                              .where((g) => g.id == selectedGovId)
                              .map((g) => g.displayName(l10n.isAr))
                              .firstOrNull;
                      try {
                        final repo = ref.read(expensesRepositoryProvider);
                        if (isEdit) {
                          await repo.editPersonalExpense(
                            actor: user,
                            original: existing,
                            newAmount: double.parse(amountCtrl.text.trim()),
                            title: titleCtrl.text,
                            notes: notesCtrl.text,
                            managerSelectedDate:
                                user.isManager ? selectedDate : null,
                            managerDeductMonthKey:
                                user.isManager ? selectedMonth : null,
                            managerGovernorateId:
                                user.isManager ? selectedGovId : null,
                            managerGovernorateName:
                                user.isManager ? selectedGovName : null,
                            newReceiptImage: receiptImage,
                            removeReceipt: removeExistingReceipt,
                          );
                        } else {
                          await repo.addPersonalExpense(
                            actor: user,
                            amount: double.parse(amountCtrl.text.trim()),
                            title: titleCtrl.text,
                            notes: notesCtrl.text,
                            managerSelectedDate:
                                user.isManager ? selectedDate : null,
                            managerDeductMonthKey:
                                user.isManager ? selectedMonth : null,
                            managerGovernorateId:
                                user.isManager ? selectedGovId : null,
                            managerGovernorateName:
                                user.isManager ? selectedGovName : null,
                            receiptImage: receiptImage,
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
