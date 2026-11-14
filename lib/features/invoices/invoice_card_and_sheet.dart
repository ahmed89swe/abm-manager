import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/server_time_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/invoice_model.dart';
import '../../providers/app_providers.dart';
import '../../services/receipt_storage_service.dart';
import '../../widgets/common_widgets.dart';
import 'create_edit_invoice_screen.dart';

class InvoiceCard extends StatelessWidget {
  const InvoiceCard({
    super.key,
    required this.invoice,
    required this.user,
    required this.onTap,
  });

  final InvoiceModel invoice;
  final AppUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusColor =
        invoice.isPaid ? AppTheme.successColor : AppTheme.dangerColor;

    final clientParts = <String>[
      if ((invoice.doctorName ?? '').isNotEmpty)
        '${l10n.tr('doctor')}: ${invoice.doctorName}',
      if ((invoice.pharmacyName ?? '').isNotEmpty)
        '${l10n.tr('pharmacy')}: ${invoice.pharmacyName}',
      if ((invoice.warehouseName ?? '').isNotEmpty)
        '${l10n.tr('warehouse')}: ${invoice.warehouseName}',
    ];

    final assigneeLabel = switch (invoice.assignmentType) {
      InvoiceAssignmentType.manager => l10n.tr('manager_himself'),
      InvoiceAssignmentType.allGovernorateDelegates =>
        l10n.tr('all_gov_delegates'),
      InvoiceAssignmentType.specificDelegate =>
        invoice.assignedDelegateName ?? l10n.tr('specific_delegate'),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      invoice.invoiceNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (invoice.receiptImageUrl != null &&
                      invoice.receiptImageUrl!.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.receipt_long_rounded, size: 18),
                    ),
                  StatusBadge(
                    label: invoice.isPaid
                        ? l10n.tr('paid')
                        : invoice.isPricePending
                            ? l10n.tr('price_pending')
                            : l10n.tr('unpaid'),
                    color: invoice.isPricePending && !invoice.isPaid
                        ? AppTheme.warningColor
                        : statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (clientParts.isNotEmpty)
                Text(
                  clientParts.join(' • '),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              const SizedBox(height: 4),
              Text(
                '${l10n.tr('responsible')}: $assigneeLabel • ${AppFormatters.formatDate(invoice.invoiceDate)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${invoice.items.length} ${l10n.tr('items')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Flexible(
                    child: Text(
                      invoice.isPricePending && invoice.totalAmount <= 0
                          ? l10n.tr('price_pending')
                          : AppFormatters.formatMoney(
                              invoice.totalAmount,
                              currency: l10n.tr('currency'),
                            ),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: invoice.isPricePending && invoice.totalAmount <= 0
                            ? AppTheme.warningColor
                            : Theme.of(context).colorScheme.primary,
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
  }
}

void showInvoiceDetailsSheet(
  BuildContext context,
  WidgetRef ref,
  InvoiceModel invoice,
  AppUser user,
) {
  final l10n = AppLocalizations.of(context);
  final isWide = MediaQuery.sizeOf(context).width >= 720;

  Widget buildContent(BuildContext ctx, ScrollController? scrollCtrl) {
    return ListView(
      controller: scrollCtrl,
      shrinkWrap: isWide,
      padding: const EdgeInsets.all(22),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.invoiceNumber,
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${invoice.governorateName} • ${AppFormatters.formatDate(invoice.invoiceDate)}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            StatusBadge(
              label: invoice.isPaid ? l10n.tr('paid') : l10n.tr('unpaid'),
              color: invoice.isPaid
                  ? AppTheme.successColor
                  : AppTheme.dangerColor,
            ),
            if (isWide) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ],
        ),
        const Divider(height: 24),
        if ((invoice.doctorName ?? '').isNotEmpty)
          _DetailRow(label: l10n.tr('doctor'), value: invoice.doctorName!),
        if ((invoice.pharmacyName ?? '').isNotEmpty)
          _DetailRow(
              label: l10n.tr('pharmacy'), value: invoice.pharmacyName!),
        if ((invoice.warehouseName ?? '').isNotEmpty)
          _DetailRow(
              label: l10n.tr('warehouse'), value: invoice.warehouseName!),
        _DetailRow(
          label: l10n.isAr ? 'المنشئ' : 'Created By',
          value: invoice.createdByName,
        ),
        if (invoice.isPaid && (invoice.paidByName ?? '').isNotEmpty)
          _DetailRow(
            label: l10n.isAr ? 'سُدد بواسطة' : 'Paid By',
            value: invoice.paidByName!,
          ),
        if (user.isManager &&
            invoice.isPaid &&
            (invoice.deductedManagerMonthKey ?? '').isNotEmpty)
          _DetailRow(
            label: l10n.isAr ? 'الشهر المقتطع منه' : 'Deducted Month',
            value: AppFormatters.formatMonthLabel(
              invoice.deductedManagerMonthKey!,
              isAr: l10n.isAr,
            ),
          ),
        if ((invoice.notes ?? '').isNotEmpty)
          _DetailRow(label: l10n.tr('notes'), value: invoice.notes!),
        const SizedBox(height: 12),
        Text(
          l10n.tr('items'),
          style: Theme.of(ctx)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...invoice.items.map(
          (item) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              title: Text(
                item.materialName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${l10n.tr('quantity')}: ${item.quantity} • ${l10n.tr('unit_price')}: ${item.unitPrice != null ? AppFormatters.formatMoney(item.unitPrice!) : l10n.tr('price_pending')}',
              ),
              trailing: Text(
                AppFormatters.formatMoney(
                  item.totalPrice,
                  currency: l10n.tr('currency'),
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.tr('total_price'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Flexible(
                child: Text(
                  AppFormatters.formatMoney(
                    invoice.totalAmount,
                    currency: l10n.tr('currency'),
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (invoice.receiptImageUrl != null &&
            invoice.receiptImageUrl!.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                showReceiptImageDialog(ctx, invoice.receiptImageUrl!),
            icon: const Icon(Icons.image_outlined),
            label: Text(l10n.tr('view_receipt')),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (!invoice.isPaid)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openPayInvoiceDialog(context, ref, invoice, user);
                },
                icon: const Icon(Icons.payments_outlined),
                label: Text(l10n.tr('pay_invoice')),
              ),
            if (user.isManager) ...[
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CreateEditInvoiceScreen(existingInvoice: invoice),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.tr('edit_invoice')),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.dangerColor,
                  side: const BorderSide(color: AppTheme.dangerColor),
                ),
                onPressed: () async {
                  final deleted = await confirmAndDeleteInvoice(
                    ctx,
                    ref,
                    invoice,
                    user,
                  );
                  if (deleted && ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.tr('delete_invoice')),
              ),
            ],
          ],
        ),
      ],
    );
  }

  if (isWide) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          child: buildContent(ctx, null),
        ),
      ),
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      builder: (_, scrollCtrl) => buildContent(ctx, scrollCtrl),
    ),
  );
}

void _openPayInvoiceDialog(
  BuildContext context,
  WidgetRef ref,
  InvoiceModel invoice,
  AppUser user,
) {
  final l10n = AppLocalizations.of(context);
  final priceControllers = invoice.items
      .map(
        (item) => TextEditingController(
          text: item.unitPrice != null && item.unitPrice! > 0
              ? item.unitPrice.toString()
              : '',
        ),
      )
      .toList();

  final now = DateTime.now();
  final boxes = user.isManager
      ? (ref.read(monthlyBoxesProvider).value ?? const [])
      : const [];
  final monthOptions = <String>{
    ...boxes.map((b) => b.monthKey),
    invoice.invoiceMonthKey,
    for (int i = 0; i < 12; i++)
      ServerTimeService.toMonthKey(DateTime(now.year, now.month - i, 1)),
  }.toList()
    ..sort((a, b) => b.compareTo(a));

  String selectedMonthKey = monthOptions.contains(invoice.invoiceMonthKey)
      ? invoice.invoiceMonthKey
      : monthOptions.first;
  PickedImageData? receiptImage;
  bool busy = false;

  final String delegateDeductMonth = invoice.invoiceDateMonthKey;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        double computedTotal = 0;
        for (var i = 0; i < invoice.items.length; i++) {
          final p = double.tryParse(priceControllers[i].text.trim()) ?? 0;
          computedTotal += p * invoice.items[i].quantity;
        }

        return AlertDialog(
          title: Text('${l10n.tr('pay_invoice')} - ${invoice.invoiceNumber}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320, maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(invoice.items.length, (i) {
                    final item = invoice.items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextFormField(
                        controller: priceControllers[i],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${item.materialName} (${l10n.tr('quantity')}: ${item.quantity})',
                          hintText: l10n.tr('unit_price'),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  Text(
                    '${l10n.tr('total_price')}: ${AppFormatters.formatMoney(computedTotal, currency: l10n.tr('currency'))}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  if (user.isManager) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedMonthKey,
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
                        if (v != null) setState(() => selectedMonthKey = v);
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 18,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${l10n.tr('delegate_pay_date_box_hint')}: ${(user.governorateName ?? '').isNotEmpty ? user.governorateName! : invoice.governorateName} • ${AppFormatters.formatMonthLabel(delegateDeductMonth, isAr: l10n.isAr)}',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    l10n.tr('attach_receipt'),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (!kIsWeb) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final f = await ReceiptStorageService.instance
                                  .pickImage(source: ImageSource.camera);
                              if (f != null) setState(() => receiptImage = f);
                            },
                            icon:
                                const Icon(Icons.camera_alt_outlined, size: 18),
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
                            if (f != null) setState(() => receiptImage = f);
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
                      padding: const EdgeInsets.only(top: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          receiptImage!.bytes,
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
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
              onPressed: busy || computedTotal <= 0
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        final updatedItems = <InvoiceItem>[];
                        for (var i = 0; i < invoice.items.length; i++) {
                          final unit =
                              double.tryParse(priceControllers[i].text.trim());
                          updatedItems.add(
                            invoice.items[i].copyWith(unitPrice: unit),
                          );
                        }
                        await ref.read(invoicesRepositoryProvider).payInvoice(
                              actor: user,
                              invoice: invoice,
                              updatedItems: updatedItems,
                              managerSelectedDeductMonthKey:
                                  user.isManager ? selectedMonthKey : null,
                              receiptImage: receiptImage,
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
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.tr('confirm')),
            ),
          ],
        );
      },
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 90, maxWidth: 130),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// نافذة تأكيد حذف الفاتورة وإرجاع تبعاتها المالية (مشتركة بين ورقة التفاصيل وشاشة التعديل)
Future<bool> confirmAndDeleteInvoice(
  BuildContext context,
  WidgetRef ref,
  InvoiceModel invoice,
  AppUser user,
) async {
  if (!user.isManager) return false;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text('${l10n.tr('delete_invoice')} • ${invoice.invoiceNumber}'),
      content: Text(
        invoice.isPaid
            ? '${l10n.tr('delete_invoice_confirm')}\n\n${l10n.tr('amount')}: ${AppFormatters.formatMoney(invoice.totalAmount, currency: l10n.tr('currency'))}\n${l10n.tr('governorate')}: ${invoice.governorateName} (${invoice.effectiveMonthKey})'
            : l10n.tr('delete_invoice_confirm'),
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
    await ref.read(invoicesRepositoryProvider).deleteInvoice(
          manager: user,
          invoice: invoice,
        );
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.tr('invoice_deleted'))),
    );
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}

/// حقل بحث موحد ضمن الفواتير (طبيب، صيدلية، مادة، مذخر، رقم فاتورة)
class InvoiceSearchBar extends StatelessWidget {
  const InvoiceSearchBar({
    super.key,
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
    this.hintText,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText ?? l10n.tr('search_invoices_hint'),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
        isDense: true,
      ),
    );
  }
}
