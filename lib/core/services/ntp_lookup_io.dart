import 'package:ntp/ntp.dart';

Future<DateTime?> lookupNtpTime() async {
  return NTP
      .now(lookUpAddress: 'time.google.com')
      .timeout(const Duration(seconds: 4));
}
