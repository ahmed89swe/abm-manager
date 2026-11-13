import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/server_time_service.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/invoice_model.dart';
import '../../models/master_data_models.dart';
import '../../providers/app_providers.dart';
import '../../services/receipt_storage_service.dart';
import '../../widgets/common_widgets.dart';

class _DraftItem {
  _DraftItem({
    this.materialId,
    this.materialName = '',
    this.quantity = 1,
    this.unitPrice,
  });

  String? materialId;
  String materialName;
  int quantity;
  double? unitPrice;

  double get total => (unitPrice ?? 0) * quantity;
}

class CreateEditInvoiceScreen extends ConsumerStatefulWidget {
  const CreateEditInvoiceScreen({
    super.key,
    this.existingInvoice,
    this.initialGovernorateId,
  });

  final InvoiceModel? existingInvoice;
  final String? initialGovernorateId;

  @override
  ConsumerState<CreateEditInvoiceScreen> createState() =>
      _CreateEditInvoiceScreenState();
}

class _CreateEditInvoiceScreenState
    extends ConsumerState<CreateEditInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _doctorNameCtrl = TextEditingController();
  final _pharmacyNameCtrl = TextEditingController();
  final _warehouseNameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _governorateId;
  InvoiceAssignmentType _assignmentType =
      InvoiceAssignmentType.allGovernorateDelegates;
  String? _selectedDelegateId;

  late DateTime _invoiceDate;
  bool _loadingServerDate = true;

  bool _payNow = false;
  String? _deductMonthKey;
  PickedImageData? _receiptImage;
  bool _isSaving = false;

  final List<_DraftItem> _items = [];

  bool get _isEditMode => widget.existingInvoice != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingInvoice;
    if (existing != null) {
      _governorateId = existing.governorateId;
      _assignmentType = existing.assignmentType;
      _selectedDelegateId = existing.assignedDelegateId;
      _doctorNameCtrl.text = existing.doctorName ?? '';
      _pharmacyNameCtrl.text = existing.pharmacyName ?? '';
      _warehouseNameCtrl.text = existing.warehouseName ?? '';
      _invoiceDate = existing.invoiceDate;
      _notesCtrl.text = existing.notes ?? '';
      _payNow = existing.isPaid;
      _deductMonthKey = existing.deductedManagerMonthKey;
      for (final item in existing.items) {
        _items.add(
          _DraftItem(
            materialId: item.materialId,
            materialName: item.materialName,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
          ),
        );
      }
      _loadingServerDate = false;
    } else {
      _governorateId = widget.initialGovernorateId;
      _invoiceDate = DateTime.now();
      _items.add(_DraftItem());
      _initTrustedTime();
    }
  }

  Future<void> _initTrustedTime() async {
    final now = await ServerTimeService.instance.getTrustedNow();
    if (!mounted) return;
    setState(() {
      _invoiceDate = now;
      _deductMonthKey ??= ServerTimeService.toMonthKey(now);
      _loadingServerDate = false;
    });
  }

  @override
  void dispose() {
    _doctorNameCtrl.dispose();
    _pharmacyNameCtrl.dispose();
    _warehouseNameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProfileProvider).value;
    if (user == null) return const SizedBox.shrink();

    final governorates = ref.watch(governoratesProvider).value ?? const [];
    final delegates = ref.watch(delegatesProvider).value ?? const [];
    final materials = ref.watch(materialsProvider).value ?? const [];
    final monthlyBoxes = ref.watch(monthlyBoxesProvider).value ?? const [];

    if (user.isDelegate && user.governorateId != null) {
      _governorateId = user.governorateId;
      _assignmentType = InvoiceAssignmentType.specificDelegate;
      _selectedDelegateId = user.uid;
    } else if (_governorateId == null && governorates.isNotEmpty) {
      _governorateId = governorates.first.id;
    }

    final govDelegates = delegates
        .where((d) => d.governorateId == _governorateId && d.isActive)
        .toList();

    final now = DateTime.now();
    final monthOptions = <String>{
      ...monthlyBoxes.map((b) => b.monthKey),
      ServerTimeService.toMonthKey(_invoiceDate),
      for (int i = 0; i < 12; i++)
        ServerTimeService.toMonthKey(DateTime(now.year, now.month - i, 1)),
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    _deductMonthKey ??= monthOptions.first;
    if (!monthOptions.contains(_deductMonthKey)) {
      _deductMonthKey = monthOptions.first;
    }

    final grandTotal = _items.fold<double>(0.0, (acc, i) => acc + i.total);
    final isWide = MediaQuery.sizeOf(context).width >= 920;

    // 1. المحافظة والمسؤولية
    final Widget assignmentCard = Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (user.isManager) ...[
                          DropdownButtonFormField<String>(
                            initialValue: governorates
                                    .any((g) => g.id == _governorateId)
                                ? _governorateId
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: '${l10n.tr('governorate')} *',
                              prefixIcon:
                                  const Icon(Icons.location_city_outlined),
                            ),
                            items: governorates
                                .map(
                                  (g) => DropdownMenuItem(
                                    value: g.id,
                                    child: Text(g.displayName(l10n.isAr)),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setState(() {
                                _governorateId = v;
                                _selectedDelegateId = null;
                              });
                            },
                            validator: (v) =>
                                v == null ? l10n.tr('required_field') : null,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<InvoiceAssignmentType>(
                            initialValue: _assignmentType,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l10n.tr('responsible'),
                              prefixIcon:
                                  const Icon(Icons.assignment_ind_outlined),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: InvoiceAssignmentType
                                    .allGovernorateDelegates,
                                child: Text(l10n.tr('all_gov_delegates')),
                              ),
                              DropdownMenuItem(
                                value: InvoiceAssignmentType.specificDelegate,
                                child: Text(l10n.tr('specific_delegate')),
                              ),
                              DropdownMenuItem(
                                value: InvoiceAssignmentType.manager,
                                child: Text(l10n.tr('manager_himself')),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _assignmentType = v;
                                  if (v !=
                                      InvoiceAssignmentType.specificDelegate) {
                                    _selectedDelegateId = null;
                                  } else if (govDelegates.isNotEmpty) {
                                    _selectedDelegateId =
                                        govDelegates.first.uid;
                                  }
                                });
                              }
                            },
                          ),
                          if (_assignmentType ==
                              InvoiceAssignmentType.specificDelegate) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: govDelegates
                                      .any((d) => d.uid == _selectedDelegateId)
                                  ? _selectedDelegateId
                                  : null,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: l10n.tr('delegate_name'),
                              ),
                              items: govDelegates
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d.uid,
                                      child: Text(d.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedDelegateId = v),
                              validator: (v) =>
                                  _assignmentType ==
                                              InvoiceAssignmentType
                                                  .specificDelegate &&
                                          v == null
                                      ? l10n.tr('required_field')
                                      : null,
                            ),
                          ],
                        ] else ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(l10n.tr('governorate')),
                            subtitle: Text(user.governorateName ?? '-'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );

    // 2. بيانات العملاء (إدخال يدوي حر: طبيب / صيدلية / مذخر)
    final Widget clientCard = Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tr('client_details'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _doctorNameCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.tr('doctor_optional'),
                            prefixIcon:
                                const Icon(Icons.medical_services_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pharmacyNameCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.tr('pharmacy_optional'),
                            prefixIcon:
                                const Icon(Icons.local_pharmacy_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _warehouseNameCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.tr('warehouse_optional'),
                            prefixIcon: const Icon(Icons.warehouse_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

    // 3. المواد (ثابتة من بيانات النظام) والكمية وسعر المفرد الاختياري
    final Widget itemsCard = Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                l10n.tr('items'),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _items.add(_DraftItem())),
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text(l10n.tr('add_item')),
                            ),
                          ],
                        ),
                        Text(
                          l10n.tr('optional_price_hint'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        ...List.generate(_items.length, (idx) {
                          final item = _items[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: materials.any(
                                                (m) => m.id == item.materialId)
                                            ? item.materialId
                                            : null,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          labelText: l10n.tr('material'),
                                        ),
                                        items: materials
                                            .map(
                                              (m) => DropdownMenuItem(
                                                value: m.id,
                                                child: Text(m.name),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) {
                                          if (v == null) return;
                                          final mat = materials
                                              .firstWhere((m) => m.id == v);
                                          setState(() {
                                            item.materialId = mat.id;
                                            item.materialName = mat.name;
                                            item.unitPrice ??=
                                                mat.defaultUnitPrice;
                                          });
                                        },
                                        validator: (v) => v == null
                                            ? l10n.tr('required_field')
                                            : null,
                                      ),
                                    ),
                                    if (_items.length > 1)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                        onPressed: () => setState(
                                          () => _items.removeAt(idx),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: item.quantity.toString(),
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          labelText: l10n.tr('quantity'),
                                        ),
                                        onChanged: (v) {
                                          setState(() {
                                            item.quantity =
                                                int.tryParse(v.trim()) ?? 1;
                                          });
                                        },
                                        validator: (v) {
                                          final q =
                                              int.tryParse(v?.trim() ?? '');
                                          return (q == null || q <= 0)
                                              ? l10n.tr('required_field')
                                              : null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        key: ValueKey(
                                            'price_${idx}_${item.materialId}'),
                                        initialValue:
                                            item.unitPrice?.toString() ?? '',
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: l10n.tr('unit_price'),
                                        ),
                                        onChanged: (v) {
                                          setState(() {
                                            item.unitPrice =
                                                double.tryParse(v.trim());
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    '${l10n.tr('total_price')}: ${AppFormatters.formatMoney(item.total, currency: l10n.tr('currency'))}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.tr('total_price'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Flexible(
                              child: Text(
                                AppFormatters.formatMoney(
                                  grandTotal,
                                  currency: l10n.tr('currency'),
                                ),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );

    // 4. التاريخ والملاحظات وخيار التسديد الفوري
    final Widget paymentCard = Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_outlined),
                          title: Text(l10n.tr('invoice_date')),
                          subtitle: Text(
                            _loadingServerDate
                                ? l10n.tr('loading')
                                : '${AppFormatters.formatDate(_invoiceDate)}${user.isDelegate ? " • ${l10n.tr('server_time_locked')}" : ""}',
                          ),
                          trailing: user.isManager
                              ? TextButton(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _invoiceDate,
                                      firstDate: DateTime(2023),
                                      lastDate: DateTime(2035),
                                    );
                                    if (picked != null) {
                                      setState(() => _invoiceDate = picked);
                                    }
                                  },
                                  child: Text(l10n.isAr ? 'تغيير' : 'Change'),
                                )
                              : const Icon(Icons.lock_outline, size: 18),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _notesCtrl,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: l10n.tr('notes'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.tr('pay_now')),
                          subtitle: grandTotal <= 0
                              ? Text(l10n.tr('optional_price_hint'))
                              : null,
                          value: _payNow && grandTotal > 0,
                          onChanged: grandTotal > 0
                              ? (v) => setState(() => _payNow = v)
                              : null,
                        ),
                        if (_payNow && grandTotal > 0) ...[
                          if (user.isManager) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _deductMonthKey,
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
                                if (v != null) {
                                  setState(() => _deductMonthKey = v);
                                }
                              },
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            l10n.tr('attach_receipt'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (!kIsWeb) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final f = await ReceiptStorageService
                                          .instance
                                          .pickImage(
                                            source: ImageSource.camera,
                                          );
                                      if (f != null) {
                                        setState(() => _receiptImage = f);
                                      }
                                    },
                                    icon: const Icon(Icons.camera_alt_outlined),
                                    label: Text(l10n.tr('camera')),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final f = await ReceiptStorageService
                                        .instance
                                        .pickImage(source: ImageSource.gallery);
                                    if (f != null) {
                                      setState(() => _receiptImage = f);
                                    }
                                  },
                                  icon:
                                      const Icon(Icons.photo_library_outlined),
                                  label: Text(l10n.tr('gallery')),
                                ),
                              ),
                            ],
                          ),
                          if (_receiptImage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  _receiptImage!.bytes,
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                );

    final Widget saveButton = SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isSaving
            ? null
            : () => _submit(
                  user: user,
                  governorates: governorates,
                  delegates: delegates,
                ),
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save_outlined),
        label: Text(l10n.tr('save')),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditMode ? l10n.tr('edit_invoice') : l10n.tr('add_invoice'),
        ),
      ),
      body: SingleChildScrollView(
        padding: ResponsiveBreakpoints.pagePadding(context),
        child: ResponsivePageContainer(
          maxWidth: 1200,
          child: Form(
            key: _formKey,
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            clientCard,
                            const SizedBox(height: 14),
                            itemsCard,
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            assignmentCard,
                            const SizedBox(height: 14),
                            paymentCard,
                            const SizedBox(height: 18),
                            saveButton,
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      assignmentCard,
                      const SizedBox(height: 12),
                      clientCard,
                      const SizedBox(height: 12),
                      itemsCard,
                      const SizedBox(height: 12),
                      paymentCard,
                      const SizedBox(height: 20),
                      saveButton,
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit({
    required AppUser user,
    required List<Governorate> governorates,
    required List<AppUser> delegates,
  }) async {
    if (!_formKey.currentState!.validate()) return;
    if (_governorateId == null) return;
    final l10n = AppLocalizations.of(context);

    final docText = _doctorNameCtrl.text.trim();
    final pharmText = _pharmacyNameCtrl.text.trim();
    final wareText = _warehouseNameCtrl.text.trim();

    if (docText.isEmpty && pharmText.isEmpty && wareText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('enter_at_least_one_client'))),
      );
      return;
    }

    final gov = governorates.firstWhere(
      (g) => g.id == _governorateId,
      orElse: () => Governorate(
        id: _governorateId!,
        nameAr: user.governorateName ?? '',
        nameEn: user.governorateName ?? '',
      ),
    );

    String? delegateName;
    if (_assignmentType == InvoiceAssignmentType.specificDelegate &&
        _selectedDelegateId != null) {
      if (user.isDelegate) {
        delegateName = user.name;
      } else {
        for (final d in delegates) {
          if (d.uid == _selectedDelegateId) {
            delegateName = d.name;
            break;
          }
        }
      }
    }

    final items = _items
        .where((i) => i.materialId != null)
        .map(
          (i) => InvoiceItem(
            materialId: i.materialId!,
            materialName: i.materialName,
            quantity: i.quantity,
            unitPrice: i.unitPrice,
          ),
        )
        .toList();

    final grandTotal = items.fold<double>(0.0, (a, b) => a + b.totalPrice);
    final effectivePayNow = _payNow && grandTotal > 0;

    setState(() => _isSaving = true);
    try {
      if (_isEditMode) {
        await ref.read(invoicesRepositoryProvider).editInvoiceByManager(
              manager: user,
              original: widget.existingInvoice!,
              governorateId: gov.id,
              governorateName: gov.displayName(l10n.isAr),
              assignmentType: _assignmentType,
              assignedDelegateId: _selectedDelegateId,
              assignedDelegateName: delegateName,
              doctorName: docText.isEmpty ? null : docText,
              pharmacyName: pharmText.isEmpty ? null : pharmText,
              warehouseName: wareText.isEmpty ? null : wareText,
              items: items,
              invoiceDate: _invoiceDate,
              notes: _notesCtrl.text.trim(),
              newStatus:
                  effectivePayNow ? InvoiceStatus.paid : InvoiceStatus.unpaid,
              newDeductedMonthKey: effectivePayNow ? _deductMonthKey : null,
              newReceiptImage: _receiptImage,
            );
      } else {
        await ref.read(invoicesRepositoryProvider).createInvoice(
              actor: user,
              governorateId: gov.id,
              governorateName: gov.displayName(l10n.isAr),
              assignmentType: _assignmentType,
              assignedDelegateId: _selectedDelegateId,
              assignedDelegateName: delegateName,
              doctorName: docText.isEmpty ? null : docText,
              pharmacyName: pharmText.isEmpty ? null : pharmText,
              warehouseName: wareText.isEmpty ? null : wareText,
              items: items,
              managerSelectedDate: user.isManager ? _invoiceDate : null,
              notes: _notesCtrl.text.trim(),
              payImmediately: effectivePayNow,
              managerSelectedDeductMonthKey:
                  user.isManager && effectivePayNow ? _deductMonthKey : null,
              receiptImage: _receiptImage,
            );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('success_saved'))),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
