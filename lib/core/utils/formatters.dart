import 'package:intl/intl.dart';

class AppFormatters {
  AppFormatters._();

  static final NumberFormat _moneyFormat = NumberFormat('#,##0.##', 'en_US');

  static String formatMoney(double amount, {String currency = ''}) {
    final formatted = _moneyFormat.format(amount);
    return currency.isEmpty ? formatted : '$formatted $currency';
  }

  static String formatDate(DateTime date, {bool includeTime = false}) {
    if (includeTime) {
      return DateFormat('yyyy-MM-dd  hh:mm a', 'en_US').format(date);
    }
    return DateFormat('yyyy-MM-dd', 'en_US').format(date);
  }

  static String formatMonthLabel(String monthKey, {required bool isAr}) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    final year = parts[0];
    final month = int.tryParse(parts[1]) ?? 1;
    if (isAr) {
      return 'شهر $month - $year';
    }
    return 'Month $month - $year';
  }
}
