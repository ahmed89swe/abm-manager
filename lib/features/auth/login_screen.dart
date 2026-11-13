import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/providers/app_preferences_provider.dart';
import '../../providers/app_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signIn(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
          );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyAuthError(e, l10n.isAr))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyAuthError(FirebaseAuthException e, bool isAr) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return isAr
            ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة'
            : 'Invalid email or password';
      case 'invalid-email':
        return isAr ? 'صيغة البريد الإلكتروني غير صحيحة' : 'Invalid email format';
      case 'user-disabled':
        return isAr ? 'هذا الحساب معطل من الإدارة' : 'Account is disabled';
      case 'network-request-failed':
        return isAr
            ? 'تعذر الاتصال بالإنترنت، تحقق من الشبكة'
            : 'Network error, please check your connection';
      case 'too-many-requests':
        return isAr
            ? 'محاولات كثيرة متكررة، يرجى الانتظار قليلاً'
            : 'Too many attempts, please wait';
      default:
        return e.message ?? e.code;
    }
  }

  void _openInitialManagerSetupDialog() {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final dialogKey = GlobalKey<FormState>();
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.tr('first_time_manager_setup')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320, maxWidth: 440),
            child: Form(
              key: dialogKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration:
                          InputDecoration(labelText: l10n.tr('manager_name')),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? l10n.tr('required_field')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: l10n.tr('email')),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? l10n.tr('required_field')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: l10n.tr('phone')),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration:
                          InputDecoration(labelText: l10n.tr('password')),
                      validator: (v) => (v == null || v.length < 6)
                          ? (l10n.isAr ? '6 أحرف على الأقل' : 'Min 6 chars')
                          : null,
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
                      if (!dialogKey.currentState!.validate()) return;
                      setDialogState(() => busy = true);
                      try {
                        await ref
                            .read(authRepositoryProvider)
                            .setupPrimaryManager(
                              name: nameCtrl.text,
                              email: emailCtrl.text,
                              password: passCtrl.text,
                              phone: phoneCtrl.text,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                        }
                      } finally {
                        if (ctx.mounted) setDialogState(() => busy = false);
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.tr('create_manager_account')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(appPreferencesProvider);
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 920;

    final topToggles = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonalIcon(
          onPressed: () =>
              ref.read(appPreferencesProvider.notifier).toggleLanguage(),
          icon: const Icon(Icons.translate_rounded, size: 18),
          label: Text(l10n.isAr ? 'English' : 'العربية'),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: l10n.tr('theme_mode'),
          onPressed: () {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            ref
                .read(appPreferencesProvider.notifier)
                .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
          },
          icon: Icon(
            prefs.themeMode == ThemeMode.dark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
          ),
        ),
      ],
    );

    final loginCard = Card(
      child: Padding(
        padding: EdgeInsets.all(isWide ? 28 : 22),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.tr('login'),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.tr('manager_setup_hint'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.tr('email'),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                validator: (v) => (v == null || !v.contains('@'))
                    ? l10n.tr('required_field')
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!_loading) _signIn();
                },
                decoration: InputDecoration(
                  labelText: l10n.tr('password'),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6)
                    ? l10n.tr('required_field')
                    : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.tr('sign_in_btn')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!isWide) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: topToggles,
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            colors: [cs.primary, cs.secondary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.28),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.tr('app_title'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.tr('app_subtitle'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    loginCard,
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: _openInitialManagerSetupDialog,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: Text(l10n.tr('first_time_manager_setup')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // تصميم الويب الواسع الاحترافي (Split Executive Portal)
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 6,
            child: _BrandShowcasePanel(l10n: l10n),
          ),
          Expanded(
            flex: 5,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 20,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: topToggles,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 36,
                          vertical: 16,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              loginCard,
                              const SizedBox(height: 16),
                              TextButton.icon(
                                onPressed: _openInitialManagerSetupDialog,
                                icon: const Icon(
                                  Icons.admin_panel_settings_outlined,
                                ),
                                label: Text(l10n.tr('first_time_manager_setup')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandShowcasePanel extends StatelessWidget {
  const _BrandShowcasePanel({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradientColors = isDark
        ? const [Color(0xFF0B2B2C), Color(0xFF102247)]
        : const [Color(0xFF0D9488), Color(0xFF1E3A8A)];

    final highlights = l10n.isAr
        ? const [
            (
              Icons.account_balance_wallet_outlined,
              'صندوق عام وصناديق محافظات فرعية',
              'متابعة دقيقة للأرصدة الشهرية والسابقة وفصل ميزانيات كل محافظة'
            ),
            (
              Icons.receipt_long_outlined,
              'فواتير محكمة بتوقيت السيرفر',
              'إدخال العملاء مرن، إرفاق وصولات السداد، ومتابعة فورية للمدفوع والمؤجل'
            ),
            (
              Icons.picture_as_pdf_outlined,
              'تقارير PDF تفصيلية ورسوم بيانية',
              'تحليل شامل حسب المحافظة والمندوب والمادة والفترة الزمنية'
            ),
            (
              Icons.notifications_active_outlined,
              'إشعارات سحابية موجهة بدقة',
              'تنبيهات لحظية للمدير والمندوبين المعنيين بكل عملية مالية'
            ),
          ]
        : const [
            (
              Icons.account_balance_wallet_outlined,
              'General & Governorate Sub-Boxes',
              'Accurate monthly tracking across current and past periods per governorate'
            ),
            (
              Icons.receipt_long_outlined,
              'Server-Verified Invoicing',
              'Flexible client entry, receipt uploads, and instant paid/deferred tracking'
            ),
            (
              Icons.picture_as_pdf_outlined,
              'Detailed PDF Reports & Analytics',
              'Granular filtering by governorate, delegate, material, and date range'
            ),
            (
              Icons.notifications_active_outlined,
              'Targeted Cloud Notifications',
              'Real-time role & delegate scoped notifications for every financial action'
            ),
          ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            start: -80,
            top: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          PositionedDirectional(
            end: -90,
            bottom: -90,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.isAr
                                ? 'بوابة ABM للإدارة المالية السحابية'
                                : 'ABM Cloud Financial Portal',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.tr('app_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.tr('app_subtitle'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ...highlights.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  item.$1,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.$2,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.$3,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.78),
                                        fontSize: 12,
                                        height: 1.35,
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
