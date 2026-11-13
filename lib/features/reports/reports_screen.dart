import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/invoice_model.dart';
import '../../models/master_data_models.dart';
import '../../models/personal_expense_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final _clientSearchCtrl = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _governorateId;
  String? _delegateId;
  String? _materialId;
  String _statusFilter = 'all'; // all | paid | unpaid

  @override
  void dispose() {
    _clientSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final governorates = ref.watch(governoratesProvider).value ?? const [];
    final delegates = ref.watch(delegatesProvider).value ?? const [];
    final materials = ref.watch(materialsProvider).value ?? const [];
    final allInvoices = ref.watch(invoicesProvider).value ?? const [];
    final allExpenses = ref.watch(personalExpensesProvider).value ?? const [];
    final boxes = ref.watch(monthlyBoxesProvider).value ?? const [];
    final govBoxes =
        ref.watch(governorateMonthlyBoxesProvider).value ?? const [];

    final queryText = _clientSearchCtrl.text.trim().toLowerCase();

    // تطبيق الفلاتر على الفواتير
    final filteredInvoices = allInvoices.where((inv) {
      if (_fromDate != null && inv.invoiceDate.isBefore(_fromDate!)) {
        return false;
      }
      if (_toDate != null &&
          inv.invoiceDate.isAfter(_toDate!.add(const Duration(days: 1)))) {
        return false;
      }
      if (_governorateId != null && inv.governorateId != _governorateId) {
        return false;
      }
      if (_delegateId != null &&
          inv.assignedDelegateId != _delegateId &&
          inv.paidByUid != _delegateId &&
          inv.createdByUid != _delegateId) {
        return false;
      }
      if (_materialId != null &&
          !inv.items.any((i) => i.materialId == _materialId)) {
        return false;
      }
      if (_statusFilter == 'paid' && !inv.isPaid) return false;
      if (_statusFilter == 'unpaid' && inv.isPaid) return false;
      if (queryText.isNotEmpty) {
        final haystack = [
          inv.invoiceNumber,
          inv.doctorName ?? '',
          inv.pharmacyName ?? '',
          inv.warehouseName ?? '',
          inv.notes ?? '',
          ...inv.items.map((i) => i.materialName),
        ].join(' ').toLowerCase();
        if (!haystack.contains(queryText)) return false;
      }
      return true;
    }).toList();

    // تطبيق الفلاتر الزمنية والمندوب والمحافظة على المصاريف
    final filteredExpenses = allExpenses.where((exp) {
      if (_fromDate != null && exp.expenseDate.isBefore(_fromDate!)) {
        return false;
      }
      if (_toDate != null &&
          exp.expenseDate.isAfter(_toDate!.add(const Duration(days: 1)))) {
        return false;
      }
      if (_governorateId != null && exp.governorateId != _governorateId) {
        return false;
      }
      if (_delegateId != null && exp.userId != _delegateId) return false;
      return true;
    }).toList();

    final paidTotal = filteredInvoices
        .where((i) => i.isPaid)
        .fold<double>(0.0, (a, b) => a + b.totalAmount);
    final unpaidTotal = filteredInvoices
        .where((i) => !i.isPaid)
        .fold<double>(0.0, (a, b) => a + b.totalAmount);
    final expensesTotal =
        filteredExpenses.fold<double>(0.0, (a, b) => a + b.amount);
    final topUpsTotal =
        boxes.fold<double>(0.0, (a, b) => a + b.totalCompanyTopUps);
    final netBoxes =
        boxes.fold<double>(0.0, (a, b) => a + b.currentBalance);
    final govBoxesBalance = govBoxes
        .where((b) => _governorateId == null || b.governorateId == _governorateId)
        .fold<double>(0.0, (a, b) => a + b.currentBalance);

    // تجميع المبالغ حسب المحافظة للرسم البياني
    final Map<String, double> byGovernorate = {};
    for (final inv in filteredInvoices) {
      byGovernorate[inv.governorateName] =
          (byGovernorate[inv.governorateName] ?? 0) + inv.totalAmount;
    }

    final isWide = MediaQuery.sizeOf(context).width >= 960;

    final Widget searchField = TextField(
      controller: _clientSearchCtrl,
      decoration: InputDecoration(
        labelText: l10n.isAr
            ? 'بحث بالعميل / رقم الفاتورة / الملاحظات'
            : 'Search by client / invoice # / notes',
        prefixIcon: const Icon(Icons.search),
      ),
      onChanged: (_) => setState(() {}),
    );

    final Widget dateRangeRow = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _fromDate ?? DateTime.now(),
                firstDate: DateTime(2023),
                lastDate: DateTime(2035),
              );
              if (d != null) setState(() => _fromDate = d);
            },
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              _fromDate == null
                  ? l10n.tr('from_date')
                  : AppFormatters.formatDate(_fromDate!),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _toDate ?? DateTime.now(),
                firstDate: DateTime(2023),
                lastDate: DateTime(2035),
              );
              if (d != null) setState(() => _toDate = d);
            },
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              _toDate == null
                  ? l10n.tr('to_date')
                  : AppFormatters.formatDate(_toDate!),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );

    final Widget govDropdown = DropdownButtonFormField<String?>(
      initialValue: _governorateId,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.tr('governorate')),
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
      onChanged: (v) => setState(() => _governorateId = v),
    );

    final Widget delegateDropdown = DropdownButtonFormField<String?>(
      initialValue: _delegateId,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.tr('delegate_name')),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(l10n.tr('all')),
        ),
        ...delegates.map(
          (d) => DropdownMenuItem<String?>(
            value: d.uid,
            child: Text(d.name),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _delegateId = v),
    );

    final Widget materialDropdown = DropdownButtonFormField<String?>(
      initialValue: _materialId,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.tr('material')),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(l10n.tr('all')),
        ),
        ...materials.map(
          (m) => DropdownMenuItem<String?>(
            value: m.id,
            child: Text(m.name),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _materialId = v),
    );

    final Widget statusSegmented = SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'all', label: Text(l10n.tr('all'))),
          ButtonSegment(value: 'paid', label: Text(l10n.tr('paid'))),
          ButtonSegment(value: 'unpaid', label: Text(l10n.tr('unpaid'))),
        ],
        selected: {_statusFilter},
        onSelectionChanged: (s) => setState(() => _statusFilter = s.first),
      ),
    );

    final Widget? chartCard = byGovernorate.isEmpty
        ? null
        : Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bar_chart_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.isAr
                              ? 'توزيع الفواتير حسب المحافظات'
                              : 'Invoices Distribution by Governorate',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: isWide ? 260 : 200,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (val, meta) {
                                final keys = byGovernorate.keys.toList();
                                final idx = val.toInt();
                                if (idx < 0 || idx >= keys.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    keys[idx],
                                    style: const TextStyle(fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: List.generate(
                          byGovernorate.length,
                          (idx) {
                            final entry = byGovernorate.entries.elementAt(idx);
                            return BarChartGroupData(
                              x: idx,
                              barRods: [
                                BarChartRodData(
                                  toY: entry.value,
                                  width: isWide ? 26 : 20,
                                  borderRadius: BorderRadius.circular(6),
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

    final Widget invoicesPreviewCard = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.tr('invoices')} (${filteredInvoices.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${l10n.tr('total_topups')}: ${AppFormatters.formatMoney(topUpsTotal)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (filteredInvoices.isEmpty)
              EmptyStateWidget(
                icon: Icons.analytics_outlined,
                message: l10n.tr('no_data'),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredInvoices.take(50).length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final inv = filteredInvoices[idx];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 2),
                    title: Text(
                      '${inv.invoiceNumber} • ${inv.governorateName}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${_clientLabel(inv, l10n)} • ${AppFormatters.formatDate(inv.invoiceDate)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          AppFormatters.formatMoney(inv.totalAmount),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: inv.isPaid
                                ? AppTheme.successColor
                                : AppTheme.dangerColor,
                          ),
                        ),
                        Text(
                          inv.isPaid ? l10n.tr('paid') : l10n.tr('unpaid'),
                          style: TextStyle(
                            fontSize: 11,
                            color: inv.isPaid
                                ? AppTheme.successColor
                                : AppTheme.dangerColor,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );

    final kpiCards = [
      WebKpiCard(
        label: l10n.tr('paid_total'),
        value: AppFormatters.formatMoney(paidTotal),
        color: AppTheme.successColor,
        icon: Icons.check_circle_outline,
      ),
      WebKpiCard(
        label: l10n.tr('unpaid_total'),
        value: AppFormatters.formatMoney(unpaidTotal),
        color: AppTheme.dangerColor,
        icon: Icons.pending_actions_outlined,
      ),
      WebKpiCard(
        label: l10n.tr('personal_expenses_total'),
        value: AppFormatters.formatMoney(expensesTotal),
        color: AppTheme.warningColor,
        icon: Icons.account_balance_wallet_outlined,
      ),
      WebKpiCard(
        label: l10n.tr('general_box'),
        value: AppFormatters.formatMoney(netBoxes),
        color: Theme.of(context).colorScheme.primary,
        icon: Icons.savings_outlined,
      ),
    ];

    return Scaffold(
      body: SingleChildScrollView(
        padding: ResponsiveBreakpoints.pagePadding(context),
        child: ResponsivePageContainer(
          maxWidth: 1240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // شريط الأدوات وتصدير التقرير
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.summarize_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.isAr
                            ? 'الملخص المالي والتصدير'
                            : 'Executive Financial Summary',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: () => _exportPdf(
                      l10n: l10n,
                      filterSummary:
                          _buildFilterSummary(l10n, governorates, delegates),
                      invoices: filteredInvoices,
                      expenses: filteredExpenses,
                      paidTotal: paidTotal,
                      unpaidTotal: unpaidTotal,
                      expensesTotal: expensesTotal,
                      netBoxes: netBoxes,
                      govBoxesBalance: govBoxesBalance,
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(l10n.tr('export_pdf')),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // لوحة الفلاتر التفصيلية
              Card(
                margin: EdgeInsets.zero,
                child: ExpansionTile(
                  initiallyExpanded: isWide,
                  leading: const Icon(Icons.filter_alt_outlined),
                  title: Text(
                    l10n.isAr ? 'خيارات التصفية والتقرير' : 'Report Filters',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _buildFilterSummary(l10n, governorates, delegates),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    if (isWide) ...[
                      Row(
                        children: [
                          Expanded(flex: 2, child: searchField),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: statusSegmented),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: dateRangeRow),
                          const SizedBox(width: 12),
                          Expanded(child: govDropdown),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: delegateDropdown),
                          const SizedBox(width: 12),
                          Expanded(child: materialDropdown),
                        ],
                      ),
                    ] else ...[
                      searchField,
                      const SizedBox(height: 10),
                      dateRangeRow,
                      const SizedBox(height: 10),
                      govDropdown,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: delegateDropdown),
                          const SizedBox(width: 8),
                          Expanded(child: materialDropdown),
                        ],
                      ),
                      const SizedBox(height: 10),
                      statusSegmented,
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _clientSearchCtrl.clear();
                            _fromDate = null;
                            _toDate = null;
                            _governorateId = null;
                            _delegateId = null;
                            _materialId = null;
                            _statusFilter = 'all';
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          l10n.isAr ? 'إعادة ضبط الفلاتر' : 'Reset Filters',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // بطاقات الملخص الإحصائي (متجاوبة مع عرض الشاشة بدون قص)
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  if (w >= 960) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < kpiCards.length; i++) ...[
                            Expanded(child: kpiCards[i]),
                            if (i < kpiCards.length - 1)
                              const SizedBox(width: 12),
                          ],
                        ],
                      ),
                    );
                  }
                  if (w >= 540) {
                    return Column(
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: kpiCards[0]),
                              const SizedBox(width: 12),
                              Expanded(child: kpiCards[1]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: kpiCards[2]),
                              const SizedBox(width: 12),
                              Expanded(child: kpiCards[3]),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      for (int i = 0; i < kpiCards.length; i++) ...[
                        kpiCards[i],
                        if (i < kpiCards.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              if (isWide && chartCard != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: chartCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 7, child: invoicesPreviewCard),
                  ],
                )
              else ...[
                if (chartCard != null) ...[
                  chartCard,
                  const SizedBox(height: 14),
                ],
                invoicesPreviewCard,
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _clientLabel(InvoiceModel inv, AppLocalizations l10n) {
    final parts = <String>[
      if ((inv.doctorName ?? '').isNotEmpty)
        '${l10n.tr('doctor')}: ${inv.doctorName}',
      if ((inv.pharmacyName ?? '').isNotEmpty)
        '${l10n.tr('pharmacy')}: ${inv.pharmacyName}',
      if ((inv.warehouseName ?? '').isNotEmpty)
        '${l10n.tr('warehouse')}: ${inv.warehouseName}',
    ];
    return parts.isEmpty ? '-' : parts.join(' | ');
  }

  String _buildFilterSummary(
    AppLocalizations l10n,
    List<Governorate> govs,
    List<AppUser> delegates,
  ) {
    final parts = <String>[];
    if (_fromDate != null) parts.add(AppFormatters.formatDate(_fromDate!));
    if (_toDate != null) parts.add(AppFormatters.formatDate(_toDate!));
    if (_governorateId != null) {
      final gov = govs.where((g) => g.id == _governorateId).firstOrNull;
      if (gov != null) parts.add(gov.displayName(l10n.isAr));
    }
    if (_delegateId != null) {
      final del = delegates.where((d) => d.uid == _delegateId).firstOrNull;
      if (del != null) parts.add(del.name);
    }
    if (_statusFilter != 'all') {
      parts.add(l10n.tr(_statusFilter));
    }
    if (parts.isEmpty) return l10n.tr('all');
    return parts.join(' • ');
  }

  Future<void> _exportPdf({
    required AppLocalizations l10n,
    required String filterSummary,
    required List<InvoiceModel> invoices,
    required List<PersonalExpenseModel> expenses,
    required double paidTotal,
    required double unpaidTotal,
    required double expensesTotal,
    required double netBoxes,
    required double govBoxesBalance,
  }) async {
    final doc = pw.Document();
    final regularFont = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();
    final isAr = l10n.isAr;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.teal50,
              border: pw.Border.all(color: PdfColors.teal300),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  isAr
                      ? 'التقرير المالي التفصيلي - ABM Manager'
                      : 'ABM Manager Detailed Financial Report',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal900,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${isAr ? "تاريخ الإصدار" : "Generated"}: ${AppFormatters.formatDate(DateTime.now(), includeTime: true)}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
                pw.Text(
                  '${l10n.tr('filter')}: $filterSummary',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // جدول الملخص المالي العام
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headers: [
              l10n.tr('total_invoices_count'),
              l10n.tr('paid_total'),
              l10n.tr('unpaid_total'),
              l10n.tr('personal_expenses_total'),
              l10n.tr('gov_sub_boxes'),
              l10n.tr('general_box'),
            ],
            data: [
              [
                '${invoices.length}',
                AppFormatters.formatMoney(paidTotal),
                AppFormatters.formatMoney(unpaidTotal),
                AppFormatters.formatMoney(expensesTotal),
                AppFormatters.formatMoney(govBoxesBalance),
                AppFormatters.formatMoney(netBoxes),
              ],
            ],
          ),
          pw.SizedBox(height: 16),

          pw.Text(
            '${isAr ? "تفاصيل الفواتير" : "Detailed Invoices"} (${invoices.length})',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),

          ...invoices.map((inv) {
            final clientStr = _clientLabel(inv, l10n);
            final responsible = switch (inv.assignmentType) {
              InvoiceAssignmentType.manager => l10n.tr('manager_himself'),
              InvoiceAssignmentType.allGovernorateDelegates =>
                l10n.tr('all_gov_delegates'),
              InvoiceAssignmentType.specificDelegate =>
                inv.assignedDelegateName ?? l10n.tr('specific_delegate'),
            };
            final sourceStr = inv.paidFromSource == 'delegate_box'
                ? (isAr ? 'صندوق المندوب' : 'Delegate Box')
                : (isAr ? 'صندوق المدير' : 'Manager Box');

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '${inv.invoiceNumber} • ${inv.governorateName} • ${AppFormatters.formatDate(inv.invoiceDate)}',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                      pw.Text(
                        '${inv.isPaid ? l10n.tr('paid') : l10n.tr('unpaid')} (${AppFormatters.formatMoney(inv.totalAmount, currency: l10n.tr('currency'))})',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                          color: inv.isPaid
                              ? PdfColors.green800
                              : PdfColors.red800,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '${isAr ? "العميل" : "Client"}: $clientStr',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    '${l10n.tr('responsible')}: $responsible | ${isAr ? "أنشئت بواسطة" : "Created by"}: ${inv.createdByName}',
                    style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                  ),
                  if (inv.isPaid)
                    pw.Text(
                      '${isAr ? "سددت بواسطة" : "Paid by"}: ${inv.paidByName ?? "-"} ($sourceStr) | ${isAr ? "شهر الاقتطاع" : "Deducted Month"}: ${inv.deductedManagerMonthKey ?? "-"}',
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                  if ((inv.notes ?? '').isNotEmpty)
                    pw.Text(
                      '${l10n.tr('notes')}: ${inv.notes}',
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                  pw.SizedBox(height: 6),
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8.5,
                    ),
                    headerDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey200),
                    cellStyle: const pw.TextStyle(fontSize: 8.5),
                    headers: [
                      l10n.tr('material'),
                      l10n.tr('quantity'),
                      l10n.tr('unit_price'),
                      l10n.tr('total_price'),
                    ],
                    data: inv.items
                        .map(
                          (item) => [
                            item.materialName,
                            '${item.quantity}',
                            item.unitPrice != null
                                ? AppFormatters.formatMoney(item.unitPrice!)
                                : l10n.tr('price_pending'),
                            AppFormatters.formatMoney(item.totalPrice),
                          ],
                        )
                        .toList(),
                  ),
                ],
              ),
            );
          }),

          if (expenses.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              '${l10n.tr('personal_expenses_total')} (${expenses.length})',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.white,
              ),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blueGrey700),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              headers: [
                l10n.tr('expense_title'),
                l10n.tr('personal_name'),
                l10n.tr('invoice_date'),
                isAr ? 'شهر الاقتطاع' : 'Deducted Month',
                l10n.tr('amount'),
                l10n.tr('notes'),
              ],
              data: expenses
                  .map(
                    (e) => [
                      e.title,
                      e.userName,
                      AppFormatters.formatDate(e.expenseDate),
                      e.deductedManagerMonthKey,
                      AppFormatters.formatMoney(e.amount),
                      e.notes ?? '-',
                    ],
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }
}
