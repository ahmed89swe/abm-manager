import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/utils/formatters.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final logsAsync = ref.watch(auditLogsProvider);
    var logs = logsAsync.value ?? const [];

    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      logs = logs
          .where((l) =>
              l.actorName.toLowerCase().contains(q) ||
              l.descriptionAr.toLowerCase().contains(q) ||
              l.descriptionEn.toLowerCase().contains(q) ||
              l.actionType.toLowerCase().contains(q))
          .toList();
    }

    final body = ResponsivePageContainer(
      maxWidth: 1160,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.tr('search'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: logsAsync.isLoading && logs.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : logs.isEmpty
                    ? EmptyStateWidget(
                        icon: Icons.history_rounded,
                        message: l10n.tr('no_data'),
                      )
                    : SingleChildScrollView(
                        padding: ResponsiveBreakpoints.pagePadding(context),
                        child: ResponsiveCardGrid(
                          maxColumns: 2,
                          twoColumnsBreakpoint: 820,
                          children: logs.map((log) {
                            final isManagerActor = log.actorRole == 'manager';
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon(
                                    isManagerActor
                                        ? Icons.admin_panel_settings_outlined
                                        : Icons.person_outline,
                                  ),
                                ),
                                title: Text(
                                  l10n.isAr
                                      ? log.descriptionAr
                                      : log.descriptionEn,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${log.actorName} • ${log.timestamp != null ? AppFormatters.formatDate(log.timestamp!, includeTime: true) : ""}',
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('audit_log'))),
      body: body,
    );
  }
}
