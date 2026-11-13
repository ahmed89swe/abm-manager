import 'package:abm_manager/core/localization/app_localizations.dart';
import 'package:abm_manager/core/theme/app_theme.dart';
import 'package:abm_manager/widgets/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BalanceHeroCard renders positive and negative balances with RTL',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.lightTheme('ar'),
        home: const Scaffold(
          body: BalanceHeroCard(
            title: 'الصندوق العام للمدير',
            subtitle: 'مجموع الصناديق الشهرية',
            balance: -250000,
            currency: 'د.ع',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الصندوق العام للمدير'), findsOneWidget);
    expect(find.text('-250,000 د.ع'), findsOneWidget);
  });
}
