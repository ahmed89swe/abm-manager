import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/providers/app_preferences_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_user.dart';
import '../../models/audit_log_model.dart';
import '../../providers/app_providers.dart';
import '../../services/notification_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/user_avatar_widget.dart';
import '../audit_log/audit_log_screen.dart';
import '../boxes/manager_boxes_screen.dart';
import '../delegates/delegates_management_screen.dart';
import '../expenses/personal_expenses_screen.dart';
import '../invoices/invoices_tab_screen.dart';
import '../master_data/master_data_screen.dart';
import '../notifications/notifications_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../version_control/version_management_screen.dart';

enum _ShellSection {
  dashboard,
  boxes,
  invoices,
  delegates,
  reports,
  expenses,
  masterData,
  auditLog,
  notifications,
  versionControl,
  settings,
  more,
}

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  late _ShellSection _activeSection;
  bool _bootstrapped = false;
  StreamSubscription<AppNotificationModel>? _liveNotifSub;

  @override
  void initState() {
    super.initState();
    _activeSection =
        widget.user.isManager ? _ShellSection.boxes : _ShellSection.dashboard;
    _bootstrapUserSession();
  }

  @override
  void dispose() {
    _liveNotifSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapUserSession() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final isAr = ref.read(appPreferencesProvider).locale.languageCode == 'ar';
    await NotificationService.instance.attachUserListener(
      widget.user,
      isAr: isAr,
    );

    _liveNotifSub = NotificationService.instance.liveNotificationsStream.listen(
      (notif) {
        if (!mounted) return;
        final langAr =
            ref.read(appPreferencesProvider).locale.languageCode == 'ar';
        final title = langAr ? notif.titleAr : notif.titleEn;
        final body = langAr ? notif.bodyAr : notif.bodyEn;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            width: MediaQuery.sizeOf(context).width >= 600 ? 440 : null,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (body.isNotEmpty)
                  Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
            action: SnackBarAction(
              label: AppLocalizations.of(context).tr('notifications'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (widget.user.isManager) {
      try {
        await ref.read(boxesRepositoryProvider).ensureCurrentMonthBoxExists();
      } catch (_) {}
    }
  }

  String _sectionTitle(_ShellSection section, AppLocalizations l10n) {
    return switch (section) {
      _ShellSection.dashboard => l10n.tr('dashboard'),
      _ShellSection.boxes => l10n.tr('boxes'),
      _ShellSection.invoices => l10n.tr('invoices'),
      _ShellSection.delegates => l10n.tr('delegates'),
      _ShellSection.reports => l10n.tr('reports'),
      _ShellSection.expenses => l10n.tr('expenses'),
      _ShellSection.masterData => l10n.tr('master_data'),
      _ShellSection.auditLog => l10n.tr('audit_log'),
      _ShellSection.notifications => l10n.tr('notifications'),
      _ShellSection.versionControl => l10n.tr('version_control'),
      _ShellSection.settings => l10n.tr('settings'),
      _ShellSection.more => l10n.tr('more'),
    };
  }

  Widget _buildSectionContent(_ShellSection section, AppUser user) {
    return switch (section) {
      _ShellSection.dashboard => _DelegateDashboardTab(user: user),
      _ShellSection.boxes => const ManagerBoxesScreen(),
      _ShellSection.invoices => const InvoicesTabScreen(),
      _ShellSection.delegates => const DelegatesManagementScreen(),
      _ShellSection.reports => const ReportsScreen(),
      _ShellSection.expenses => const PersonalExpensesScreen(embedded: true),
      _ShellSection.masterData => const MasterDataScreen(embedded: true),
      _ShellSection.auditLog => const AuditLogScreen(embedded: true),
      _ShellSection.notifications => const NotificationsScreen(embedded: true),
      _ShellSection.versionControl =>
        const VersionManagementScreen(embedded: true),
      _ShellSection.settings => const SettingsScreen(embedded: true),
      _ShellSection.more => user.isManager
          ? _ManagerMoreTab(user: user)
          : _DelegateMoreTab(user: user),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProfileProvider).value ?? widget.user;
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    final prefs = ref.watch(appPreferencesProvider);
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final isTablet = ResponsiveBreakpoints.isTabletOrLarger(context) && !isDesktop;

    // الوجهات الكاملة لنسخة الويب وسطح المكتب
    final primaryDesktopItems = user.isManager
        ? [
            (
              _ShellSection.boxes,
              Icons.account_balance_wallet_outlined,
              Icons.account_balance_wallet,
              l10n.tr('boxes')
            ),
            (
              _ShellSection.invoices,
              Icons.receipt_long_outlined,
              Icons.receipt_long,
              l10n.tr('invoices')
            ),
            (
              _ShellSection.delegates,
              Icons.people_outline,
              Icons.people,
              l10n.tr('delegates')
            ),
            (
              _ShellSection.reports,
              Icons.analytics_outlined,
              Icons.analytics,
              l10n.tr('reports')
            ),
            (
              _ShellSection.expenses,
              Icons.wallet_outlined,
              Icons.wallet,
              l10n.tr('expenses')
            ),
          ]
        : [
            (
              _ShellSection.dashboard,
              Icons.home_outlined,
              Icons.home,
              l10n.tr('dashboard')
            ),
            (
              _ShellSection.invoices,
              Icons.receipt_long_outlined,
              Icons.receipt_long,
              l10n.tr('invoices')
            ),
            (
              _ShellSection.expenses,
              Icons.wallet_outlined,
              Icons.wallet,
              l10n.tr('expenses')
            ),
          ];

    final adminDesktopItems = user.isManager
        ? [
            (
              _ShellSection.masterData,
              Icons.dataset_outlined,
              Icons.dataset,
              l10n.tr('master_data')
            ),
            (
              _ShellSection.auditLog,
              Icons.history_rounded,
              Icons.history_rounded,
              l10n.tr('audit_log')
            ),
            (
              _ShellSection.notifications,
              Icons.notifications_outlined,
              Icons.notifications,
              l10n.tr('notifications')
            ),
            (
              _ShellSection.versionControl,
              Icons.system_update_outlined,
              Icons.system_update,
              l10n.tr('version_control')
            ),
            (
              _ShellSection.settings,
              Icons.settings_outlined,
              Icons.settings,
              l10n.tr('settings')
            ),
          ]
        : [
            (
              _ShellSection.auditLog,
              Icons.history_rounded,
              Icons.history_rounded,
              l10n.tr('audit_log')
            ),
            (
              _ShellSection.notifications,
              Icons.notifications_outlined,
              Icons.notifications,
              l10n.tr('notifications')
            ),
            (
              _ShellSection.settings,
              Icons.settings_outlined,
              Icons.settings,
              l10n.tr('settings')
            ),
          ];

    final allDesktopItems = [...primaryDesktopItems, ...adminDesktopItems];

    // معالجة التبديل السلس عند تغيير عرض المتصفح
    if (isDesktop || isTablet) {
      if (_activeSection == _ShellSection.more) {
        _activeSection = allDesktopItems.first.$1;
      }
      if (!allDesktopItems.any((e) => e.$1 == _activeSection)) {
        _activeSection = allDesktopItems.first.$1;
      }
    }

    // الموبايل (< 720px): شريط سفلي أنيق ومألوف
    if (!isDesktop && !isTablet) {
      final mobileTabs = user.isManager
          ? [
              (
                _ShellSection.boxes,
                Icons.account_balance_wallet_outlined,
                Icons.account_balance_wallet,
                l10n.tr('boxes')
              ),
              (
                _ShellSection.invoices,
                Icons.receipt_long_outlined,
                Icons.receipt_long,
                l10n.tr('invoices')
              ),
              (
                _ShellSection.delegates,
                Icons.people_outline,
                Icons.people,
                l10n.tr('delegates')
              ),
              (
                _ShellSection.reports,
                Icons.analytics_outlined,
                Icons.analytics,
                l10n.tr('reports')
              ),
              (
                _ShellSection.more,
                Icons.grid_view_outlined,
                Icons.grid_view,
                l10n.tr('more')
              ),
            ]
          : [
              (
                _ShellSection.dashboard,
                Icons.home_outlined,
                Icons.home,
                l10n.tr('dashboard')
              ),
              (
                _ShellSection.invoices,
                Icons.receipt_long_outlined,
                Icons.receipt_long,
                l10n.tr('invoices')
              ),
              (
                _ShellSection.expenses,
                Icons.wallet_outlined,
                Icons.wallet,
                l10n.tr('expenses')
              ),
              (
                _ShellSection.more,
                Icons.settings_outlined,
                Icons.settings,
                l10n.tr('more')
              ),
            ];

      final currentMobileIdx =
          mobileTabs.indexWhere((e) => e.$1 == _activeSection);
      final effectiveSection =
          currentMobileIdx == -1 ? _ShellSection.more : _activeSection;
      final effectiveIdx = currentMobileIdx == -1
          ? mobileTabs.length - 1
          : currentMobileIdx;

      return Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                child: UserAvatarWidget(user: user, radius: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sectionTitle(effectiveSection, l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${user.name}${user.governorateName != null ? " • ${user.governorateName}" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            _NotificationBellButton(
              unreadCount: unreadCount,
              tooltip: l10n.tr('notifications'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
          ],
        ),
        body: _buildSectionContent(effectiveSection, user),
        bottomNavigationBar: NavigationBar(
          selectedIndex: effectiveIdx,
          onDestinationSelected: (idx) =>
              setState(() => _activeSection = mobileTabs[idx].$1),
          destinations: mobileTabs
              .map(
                (t) => NavigationDestination(
                  icon: Icon(t.$2),
                  selectedIcon: Icon(t.$3),
                  label: t.$4,
                ),
              )
              .toList(),
        ),
      );
    }

    // الويب وسطح المكتب والأجهزة اللوحية (>= 720px)
    final cs = Theme.of(context).colorScheme;
    final trustedNowAsync = ref.watch(trustedNowProvider);

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop)
            _DesktopSidebar(
              user: user,
              l10n: l10n,
              activeSection: _activeSection,
              primaryItems: primaryDesktopItems,
              adminItems: adminDesktopItems,
              unreadCount: unreadCount,
              onSelect: (s) => setState(() => _activeSection = s),
              onOpenSettings: () =>
                  setState(() => _activeSection = _ShellSection.settings),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                border: BorderDirectional(
                  end: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: NavigationRail(
                selectedIndex: allDesktopItems
                    .indexWhere((e) => e.$1 == _activeSection)
                    .clamp(0, allDesktopItems.length - 1),
                labelType: NavigationRailLabelType.selected,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () =>
                        setState(() => _activeSection = _ShellSection.settings),
                    child: UserAvatarWidget(user: user, radius: 20),
                  ),
                ),
                destinations: allDesktopItems
                    .map(
                      (item) => NavigationRailDestination(
                        icon: Icon(item.$2),
                        selectedIcon: Icon(item.$3),
                        label: Text(item.$4),
                      ),
                    )
                    .toList(),
                onDestinationSelected: (idx) =>
                    setState(() => _activeSection = allDesktopItems[idx].$1),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                // شريط الرأس التنفيذي للويب
                Container(
                  height: 68,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              _sectionTitle(_activeSection, l10n),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 12),
                            if (!isDesktop)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  user.name,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (trustedNowAsync.hasValue)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: cs.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_done_outlined,
                                size: 15,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                AppFormatters.formatDate(
                                  trustedNowAsync.value!,
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => ref
                            .read(appPreferencesProvider.notifier)
                            .toggleLanguage(),
                        icon: const Icon(Icons.translate_rounded, size: 16),
                        label: Text(l10n.isAr ? 'EN' : 'عربي'),
                      ),
                      const SizedBox(width: 6),
                      IconButton.outlined(
                        tooltip: l10n.tr('theme_mode'),
                        onPressed: () {
                          final isDark =
                              Theme.of(context).brightness == Brightness.dark;
                          ref
                              .read(appPreferencesProvider.notifier)
                              .setThemeMode(
                                isDark ? ThemeMode.light : ThemeMode.dark,
                              );
                        },
                        icon: Icon(
                          prefs.themeMode == ThemeMode.dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _NotificationBellButton(
                        unreadCount: unreadCount,
                        tooltip: l10n.tr('notifications'),
                        onPressed: () => setState(
                          () => _activeSection = _ShellSection.notifications,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey(_activeSection),
                      child: _buildSectionContent(_activeSection, user),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.user,
    required this.l10n,
    required this.activeSection,
    required this.primaryItems,
    required this.adminItems,
    required this.unreadCount,
    required this.onSelect,
    required this.onOpenSettings,
  });

  final AppUser user;
  final AppLocalizations l10n;
  final _ShellSection activeSection;
  final List<(_ShellSection, IconData, IconData, String)> primaryItems;
  final List<(_ShellSection, IconData, IconData, String)> adminItems;
  final int unreadCount;
  final ValueChanged<_ShellSection> onSelect;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 268,
      decoration: BoxDecoration(
        color: cs.surface,
        border: BorderDirectional(
          end: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          // شعار النظام في أعلى القائمة الجانبية
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.secondary],
                    ),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ABM Manager',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        user.isManager
                            ? (l10n.isAr ? 'لوحة تحكم المدير' : 'Manager Portal')
                            : (l10n.isAr ? 'بوابة المندوب' : 'Delegate Portal'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              children: [
                _SidebarGroupLabel(
                  label: l10n.isAr
                      ? 'المالية والعمليات'
                      : 'FINANCE & OPERATIONS',
                ),
                ...primaryItems.map(
                  (item) => _SidebarNavTile(
                    icon: item.$2,
                    selectedIcon: item.$3,
                    label: item.$4,
                    selected: activeSection == item.$1,
                    onTap: () => onSelect(item.$1),
                  ),
                ),
                const SizedBox(height: 16),
                _SidebarGroupLabel(
                  label: l10n.isAr ? 'الإدارة والنظام' : 'SYSTEM & SETTINGS',
                ),
                ...adminItems.map(
                  (item) => _SidebarNavTile(
                    icon: item.$2,
                    selectedIcon: item.$3,
                    label: item.$4,
                    selected: activeSection == item.$1,
                    badgeCount: item.$1 == _ShellSection.notifications
                        ? unreadCount
                        : 0,
                    onTap: () => onSelect(item.$1),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onOpenSettings,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    UserAvatarWidget(user: user, radius: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          Text(
                            user.governorateName ?? user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
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

class _SidebarGroupLabel extends StatelessWidget {
  const _SidebarGroupLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

class _SidebarNavTile extends StatelessWidget {
  const _SidebarNavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color:
            selected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 20,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13.5,
                      color: selected ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationBellButton extends StatelessWidget {
  const _NotificationBellButton({
    required this.unreadCount,
    required this.tooltip,
    required this.onPressed,
  });

  final int unreadCount;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: tooltip,
          icon: const Icon(Icons.notifications_outlined),
          onPressed: onPressed,
        ),
        if (unreadCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppTheme.dangerColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DelegateDashboardTab extends ConsumerWidget {
  const _DelegateDashboardTab({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final invoices = ref.watch(invoicesProvider).value ?? const [];
    final expenses = ref.watch(personalExpensesProvider).value ?? const [];
    final trustedNowAsync = ref.watch(trustedNowProvider);

    final paidByMe = invoices
        .where((i) => i.isPaid && i.paidByUid == user.uid)
        .fold<double>(0.0, (a, b) => a + b.totalAmount);
    final unpaidCount = invoices.where((i) => !i.isPaid).length;
    final myExpenses = expenses.fold<double>(0.0, (a, b) => a + b.amount);

    return ResponsivePageContainer(
      maxWidth: 1200,
      child: ListView(
        padding: ResponsiveBreakpoints.pagePadding(context),
        children: [
          // يرى المندوب صندوقه الافتراضي فقط دون أي اطلاع على صندوق المدير العام/الشهري
          BalanceHeroCard(
            title: l10n.tr('delegate_virtual_box'),
            subtitle: user.governorateName ?? '',
            balance: user.virtualBoxBalance,
            currency: l10n.tr('currency'),
            footerWidgets: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tr('paid_total'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    AppFormatters.formatMoney(paidByMe),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tr('personal_expenses_total'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    AppFormatters.formatMoney(myExpenses),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          ResponsiveCardGrid(
            maxColumns: 3,
            twoColumnsBreakpoint: 640,
            threeColumnsBreakpoint: 960,
            children: [
              WebKpiCard(
                label: l10n.tr('paid_total'),
                value: AppFormatters.formatMoney(
                  paidByMe,
                  currency: l10n.tr('currency'),
                ),
                icon: Icons.check_circle_outline,
                color: AppTheme.successColor,
              ),
              WebKpiCard(
                label: l10n.tr('unpaid'),
                value: '$unpaidCount',
                icon: Icons.pending_actions_outlined,
                color: unpaidCount > 0
                    ? AppTheme.warningColor
                    : Theme.of(context).colorScheme.primary,
              ),
              WebKpiCard(
                label: l10n.tr('personal_expenses_total'),
                value: AppFormatters.formatMoney(
                  myExpenses,
                  currency: l10n.tr('currency'),
                ),
                icon: Icons.account_balance_wallet_outlined,
                color: AppTheme.dangerColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: Text(l10n.tr('server_time_badge')),
              subtitle: Text(
                trustedNowAsync.hasValue
                    ? AppFormatters.formatDate(
                        trustedNowAsync.value!,
                        includeTime: true,
                      )
                    : l10n.tr('loading'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerMoreTab extends StatelessWidget {
  const _ManagerMoreTab({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ResponsivePageContainer(
      maxWidth: 820,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MoreItemCard(
            icon: Icons.dataset_outlined,
            title: l10n.tr('master_data'),
            subtitle: '${l10n.tr('governorates')} • ${l10n.tr('materials')}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MasterDataScreen()),
            ),
          ),
          _MoreItemCard(
            icon: Icons.wallet_outlined,
            title: l10n.tr('expenses'),
            subtitle: l10n.isAr
                ? 'إدارة المصاريف الشخصية للمدير والمندوبين'
                : 'Manage manager & delegates personal expenses',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PersonalExpensesScreen()),
            ),
          ),
          _MoreItemCard(
            icon: Icons.history_rounded,
            title: l10n.tr('audit_log'),
            subtitle: l10n.isAr
                ? 'سجل كافة العمليات التي حدثت في النظام'
                : 'Complete log of all system operations',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuditLogScreen()),
            ),
          ),
          _MoreItemCard(
            icon: Icons.system_update_outlined,
            title: l10n.tr('version_control'),
            subtitle: l10n.isAr
                ? 'إدارة الإصدارات وإرسال التحديثات للمندوبين'
                : 'Manage app versions & push updates to delegates',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const VersionManagementScreen(),
              ),
            ),
          ),
          _MoreItemCard(
            icon: Icons.settings_outlined,
            title: l10n.tr('settings'),
            subtitle:
                '${l10n.tr('profile')} • ${l10n.tr('language')} • ${l10n.tr('theme_mode')}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _DelegateMoreTab extends StatelessWidget {
  const _DelegateMoreTab({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ResponsivePageContainer(
      maxWidth: 820,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MoreItemCard(
            icon: Icons.history_rounded,
            title: l10n.tr('audit_log'),
            subtitle: l10n.isAr ? 'سجل عملياتي' : 'My activity log',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuditLogScreen()),
            ),
          ),
          _MoreItemCard(
            icon: Icons.notifications_outlined,
            title: l10n.tr('notifications'),
            subtitle: l10n.isAr ? 'مركز الإشعارات' : 'Notification center',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          _MoreItemCard(
            icon: Icons.settings_outlined,
            title: l10n.tr('settings'),
            subtitle:
                '${l10n.tr('profile')} • ${l10n.tr('language')} • ${l10n.tr('theme_mode')}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreItemCard extends StatelessWidget {
  const _MoreItemCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
