import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ntp_lookup_stub.dart' if (dart.library.io) 'ntp_lookup_io.dart';

/// خدمة جلب التوقيت الحقيقي من الإنترنت / السيرفر وليس من ساعة جهاز المستخدم.
/// تُستخدم لإقفال تاريخ الفواتير والمصاريف عند المندوب ومنع التلاعب بوقت الجهاز.
class ServerTimeService {
  ServerTimeService._();
  static final ServerTimeService instance = ServerTimeService._();

  Duration? _cachedOffset;
  DateTime? _lastSyncAt;

  /// إرجاع الوقت الحالي الموثوق من السيرفر/NTP
  Future<DateTime> getTrustedNow({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedOffset != null &&
        _lastSyncAt != null &&
        DateTime.now().difference(_lastSyncAt!).inMinutes < 15) {
      return DateTime.now().add(_cachedOffset!);
    }

    // المحاولة الأولى على تطبيقات الجوال/سطح المكتب: خادم NTP
    if (!kIsWeb) {
      try {
        final ntpTime = await lookupNtpTime();
        if (ntpTime != null) {
          _cachedOffset = ntpTime.difference(DateTime.now());
          _lastSyncAt = DateTime.now();
          return ntpTime;
        }
      } catch (e) {
        debugPrint('NTP sync fallback: $e');
      }

      // المحاولة الثانية على الموبايل: ترويسة Date من خادم HTTP موثوق
      try {
        final response = await http
            .head(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 4));
        final dateHeader = response.headers['date'];
        if (dateHeader != null) {
          final serverUtc = _parseHttpDate(dateHeader);
          if (serverUtc != null) {
            final localNow = serverUtc.toLocal();
            _cachedOffset = localNow.difference(DateTime.now());
            _lastSyncAt = DateTime.now();
            return localNow;
          }
        }
      } catch (e) {
        debugPrint('HTTP time sync fallback: $e');
      }
    } else {
      // على الويب نستخدم نقطة وقت تدعم CORS بأمان دون حظر المتصفح
      try {
        final response = await http
            .get(Uri.parse('https://timeapi.io/api/Time/current/zone?timeZone=UTC'))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final iso = data['dateTime']?.toString();
          if (iso != null && iso.isNotEmpty) {
            final utc = DateTime.parse(iso.endsWith('Z') ? iso : '${iso}Z');
            final localNow = utc.toLocal();
            _cachedOffset = localNow.difference(DateTime.now());
            _lastSyncAt = DateTime.now();
            return localNow;
          }
        }
      } catch (e) {
        debugPrint('Web HTTP time sync fallback: $e');
      }
    }

    if (_cachedOffset != null) {
      return DateTime.now().add(_cachedOffset!);
    }
    return DateTime.now();
  }

  /// استخراج مفتاح الشهر بصيغة YYYY-MM
  static String toMonthKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  /// تحويل مفتاح الشهر إلى رقم الشهر والسنة
  static ({int year, int month}) parseMonthKey(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length == 2) {
      return (
        year: int.tryParse(parts[0]) ?? DateTime.now().year,
        month: int.tryParse(parts[1]) ?? DateTime.now().month,
      );
    }
    final now = DateTime.now();
    return (year: now.year, month: now.month);
  }

  static DateTime? _parseHttpDate(String raw) {
    try {
      final parts = raw.split(' ');
      if (parts.length < 5) return null;
      final day = int.parse(parts[1]);
      const months = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final month = months[parts[2]];
      if (month == null) return null;
      final year = int.parse(parts[3]);
      final timeParts = parts[4].split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = int.parse(timeParts[2]);
      return DateTime.utc(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}
