import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/utils/formatters.dart';
import '../../providers/app_providers.dart';
import '../../services/notification_service.dart';
import '../../widgets/browser_notification_widgets.dart';
import '../../widgets/common_widgets.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProfileProvider).value;
    final notifs = ref.watch(notificationsProvider).value ?? const [];

    final body = ResponsivePageContainer(
      maxWidth: 1100,
      child: Column(
        children: [
          if (kIsWeb)
            Padding(
              padding: ResponsiveBreakpoints.pagePadding(context)
                  .copyWith(bottom: 0),
              child: const BrowserNotificationBanner(),
            ),
          Expanded(
            child: notifs.isEmpty
                ? EmptyStateWidget(
                    icon: Icons.notifications_none_rounded,
                    message: l10n.tr('no_data'),
                  )
                : SingleChildScrollView(
                    padding: ResponsiveBreakpoints.pagePadding(context),
                    child: ResponsiveCardGrid(
                      maxColumns: 2,
                      twoColumnsBreakpoint: 820,
                      children: notifs.map((n) {
                        final isRead = user != null && n.isReadBy(user.uid);
                        return Card(
                          color: isRead
                              ? null
                              : Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.35),
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                isRead
                                    ? Icons.notifications_outlined
                                    : Icons.notifications_active_rounded,
                              ),
                            ),
                            title: Text(
                              l10n.isAr ? n.titleAr : n.titleEn,
                              style: TextStyle(
                                fontWeight:
                                    isRead ? FontWeight.w600 : FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${l10n.isAr ? n.bodyAr : n.bodyEn}\n${n.createdAt != null ? AppFormatters.formatDate(n.createdAt!, includeTime: true) : ""}',
                            ),
                            isThreeLine: true,
                            onTap: () {
                              if (user != null && !isRead) {
                                NotificationService.instance
                                    .markAsRead(n.id, user.uid);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );

    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('notifications'))),
      body: body,
    );
  }
}
