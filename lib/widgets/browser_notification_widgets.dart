import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/localization/app_localizations.dart';
import '../core/theme/app_theme.dart';
import '../services/notification_service.dart';

class BrowserNotificationBanner extends StatefulWidget {
  const BrowserNotificationBanner({super.key});

  @override
  State<BrowserNotificationBanner> createState() =>
      _BrowserNotificationBannerState();
}

class _BrowserNotificationBannerState extends State<BrowserNotificationBanner> {
  bool _dismissed = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _dismissed) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final svc = NotificationService.instance;
    final perm = svc.browserPermissionStatus;
    final isIosWeb = defaultTargetPlatform == TargetPlatform.iOS;

    if (perm == 'granted') return const SizedBox.shrink();
    if (perm == 'unsupported' && !isIosWeb) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isDenied = perm == 'denied';
    final isIosHint = perm == 'unsupported' && isIosWeb;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: isDenied
          ? AppTheme.warningColor.withValues(alpha: 0.12)
          : cs.primaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDenied
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                  color: isDenied ? AppTheme.warningColor : cs.primary,
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Text(
                    isIosHint
                        ? l10n.tr('notifications_ios_hint')
                        : isDenied
                            ? '${l10n.tr('notifications_blocked')}. ${l10n.tr('browser_notif_settings_hint')}'
                            : l10n.tr('browser_notif_banner'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDenied && !isIosHint)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final res = await svc.requestBrowserPermission();
                            if (!context.mounted) return;
                            setState(() => _busy = false);
                            if (res == 'granted') {
                              await svc.showLocalNotification(
                                id: DateTime.now().millisecondsSinceEpoch %
                                    100000,
                                title: l10n.tr('notifications_enabled'),
                                body: l10n.tr('browser_notifications_desc'),
                              );
                            }
                          },
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.notifications_active, size: 17),
                    label: Text(l10n.tr('enable_now')),
                  ),
                IconButton(
                  tooltip: l10n.tr('cancel'),
                  onPressed: () => setState(() => _dismissed = true),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BrowserNotificationsCard extends StatefulWidget {
  const BrowserNotificationsCard({super.key});

  @override
  State<BrowserNotificationsCard> createState() =>
      _BrowserNotificationsCardState();
}

class _BrowserNotificationsCardState extends State<BrowserNotificationsCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final svc = NotificationService.instance;
    final perm = svc.browserPermissionStatus;
    final isIosWeb = defaultTargetPlatform == TargetPlatform.iOS;

    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    switch (perm) {
      case 'granted':
        statusColor = AppTheme.successColor;
        statusText = l10n.tr('notifications_enabled');
        statusIcon = Icons.check_circle_outline_rounded;
      case 'denied':
        statusColor = AppTheme.dangerColor;
        statusText = l10n.tr('notifications_blocked');
        statusIcon = Icons.block_rounded;
      case 'unsupported':
        statusColor = AppTheme.warningColor;
        statusText = isIosWeb
            ? l10n.tr('notifications_ios_hint')
            : l10n.tr('notifications_not_enabled');
        statusIcon = Icons.info_outline_rounded;
      default:
        statusColor = AppTheme.warningColor;
        statusText = l10n.tr('notifications_not_enabled');
        statusIcon = Icons.notifications_none_rounded;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.tr('browser_notifications'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.tr('browser_notifications_desc'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, size: 18, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (perm == 'denied') ...[
              const SizedBox(height: 8),
              Text(
                l10n.tr('browser_notif_settings_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (perm == 'default' || perm == 'granted') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (perm == 'default')
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              await svc.requestBrowserPermission();
                              if (mounted) setState(() => _busy = false);
                            },
                      icon: _busy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.notifications_active, size: 18),
                      label: Text(l10n.tr('enable_now')),
                    ),
                  if (perm == 'granted')
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              await svc.showLocalNotification(
                                id: DateTime.now().millisecondsSinceEpoch %
                                    100000,
                                title: l10n.tr('app_title'),
                                body: l10n.tr('test_notification_sent'),
                              );
                              if (!context.mounted) return;
                              setState(() => _busy = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.tr('test_notification_sent'),
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: Text(l10n.tr('test_notification')),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
