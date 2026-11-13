import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/localization/app_localizations.dart';
import 'core/providers/app_preferences_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/main_shell_screen.dart';
import 'features/version_control/version_check_gate.dart';
import 'firebase_options.dart';
import 'providers/app_providers.dart';
import 'services/notification_service.dart';

/// مفتاح ملاحة جذري لإغلاق كافة النوافذ المنبثقة فور تسجيل الخروج
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  runApp(const ProviderScope(child: AbmManagerApp()));
}

class AbmManagerApp extends ConsumerWidget {
  const AbmManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPreferencesProvider);
    final lang = prefs.locale.languageCode;

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'ABM Manager',
      locale: prefs.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme(lang),
      darkTheme: AppTheme.darkTheme(lang),
      themeMode: prefs.themeMode,
      home: const VersionCheckGate(child: _AuthGate()),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(firebaseAuthStateProvider, (_, next) {
      if (next.value == null) {
        rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });

    final authAsync = ref.watch(firebaseAuthStateProvider);

    return authAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        body: Center(child: Text('$err')),
      ),
      data: (firebaseUser) {
        if (firebaseUser == null) {
          return const LoginScreen();
        }
        final profileAsync = ref.watch(currentUserProfileProvider);
        return profileAsync.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$err', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        rootNavigatorKey.currentState
                            ?.popUntil((route) => route.isFirst);
                        ref.read(authRepositoryProvider).signOut();
                      },
                      child: Text(AppLocalizations.of(context).tr('logout')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          data: (user) {
            if (user == null || !user.isActive) {
              return const LoginScreen();
            }
            return MainShellScreen(user: user);
          },
        );
      },
    );
  }
}
