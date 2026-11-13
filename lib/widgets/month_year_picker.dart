import 'package:flutter/material.dart';
import '../core/localization/app_localizations.dart';
import '../core/services/server_time_service.dart';

/// أداة اختيار الشهر والسنة (الحالي أو أي شهر سابق) بشكل موحّد ومتجاوب
class MonthYearSelectorRow extends StatelessWidget {
  const MonthYearSelectorRow({
    super.key,
    required this.selectedYear,
    required this.selectedMonth,
    required this.maxYear,
    required this.onYearChanged,
    required this.onMonthChanged,
  });

  final int selectedYear;
  final int selectedMonth;
  final int maxYear;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final years = List.generate(6, (i) => maxYear - i);
    final months = List.generate(12, (i) => i + 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int>(
                initialValue: selectedMonth,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.tr('select_month'),
                ),
                items: months
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(l10n.monthName(m)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onMonthChanged(v);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                initialValue:
                    years.contains(selectedYear) ? selectedYear : years.first,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.tr('select_year'),
                ),
                items: years
                    .map(
                      (y) => DropdownMenuItem(
                        value: y,
                        child: Text('$y'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onYearChanged(v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.tr('past_or_current_month'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  static String toMonthKey(int year, int month) =>
      ServerTimeService.toMonthKey(DateTime(year, month, 1));
}
