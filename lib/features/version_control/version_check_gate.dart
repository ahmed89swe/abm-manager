import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/audit_log_model.dart';
import '../../providers/app_providers.dart';

/// مقارنة رقمَي إصدار (مثل 1.0.0 مقابل 1.0.2): تعيد true إذا كان [current] أقدم من [target]
bool isVersionOlder(String current, String target) {
  List<int> parseParts(String raw) {
    final cleaned = raw.trim().split('+').first.split('-').first;
    if (cleaned.isEmpty) return const [0];
    return cleaned
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  final curParts = parseParts(current);
  final tgtParts = parseParts(target);
  final maxLen =
      curParts.length > tgtParts.length ? curParts.length : tgtParts.length;

  for (var i = 0; i < maxLen; i++) {
    final c = i < curParts.length ? curParts[i] : 0;
    final t = i < tgtParts.length ? tgtParts[i] : 0;
    if (c < t) return true;
    if (c > t) return false;
  }
  return false;
}

class VersionCheckGate extends ConsumerStatefulWidget {
  const VersionCheckGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VersionCheckGate> createState() => _VersionCheckGateState();
}

class _VersionCheckGateState extends ConsumerState<VersionCheckGate> {
  String _currentVersionName = '1.0.0';
  bool _optionalDismissed = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted && info.version.isNotEmpty) {
        setState(() {
          _currentVersionName = info.version;
        });
      }
    } catch (_) {}
  }

  Future<void> _launchUpdateUrl(String url) async {
    if (url.trim().isEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return widget.child;
    final config = ref.watch(versionConfigProvider).value;
    if (config == null) return widget.child;

    final user = ref.watch(currentUserProfileProvider).value;
    final isDelegate = user != null && user.isDelegate;
    final hasUpdate =
        isVersionOlder(_currentVersionName, config.latestVersionName);

    // التحديث الإجباري يشمل المندوبين فقط ولا يُطبق على المدير إطلاقاً
    final needsMandatoryUpdate =
        isDelegate && config.isForceUpdate && hasUpdate;

    // التحديث الاختياري يُعرض للمستخدم المسجل فقط عند توفر نسخة أحدث
    final hasOptionalUpdate = user != null &&
        !needsMandatoryUpdate &&
        !_optionalDismissed &&
        !config.isForceUpdate &&
        hasUpdate;

    if (needsMandatoryUpdate) {
      return _UpdateOverlayScreen(
        config: config,
        isMandatory: true,
        onUpdatePressed: () => _launchUpdateUrl(config.downloadUrl),
      );
    }

    if (hasOptionalUpdate) {
      return Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: Material(
              color: Colors.black54,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _UpdateCard(
                      config: config,
                      isMandatory: false,
                      onUpdatePressed: () =>
                          _launchUpdateUrl(config.downloadUrl),
                      onLaterPressed: () =>
                          setState(() => _optionalDismissed = true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return widget.child;
  }
}

class _UpdateOverlayScreen extends StatelessWidget {
  const _UpdateOverlayScreen({
    required this.config,
    required this.isMandatory,
    required this.onUpdatePressed,
  });

  final AppVersionConfig config;
  final bool isMandatory;
  final VoidCallback onUpdatePressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _UpdateCard(
                config: config,
                isMandatory: isMandatory,
                onUpdatePressed: onUpdatePressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.config,
    required this.isMandatory,
    required this.onUpdatePressed,
    this.onLaterPressed,
  });

  final AppVersionConfig config;
  final bool isMandatory;
  final VoidCallback onUpdatePressed;
  final VoidCallback? onLaterPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAr = l10n.isAr;
    final notes = isAr ? config.releaseNotesAr : config.releaseNotesEn;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(
                Icons.system_update_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${l10n.tr('update_available')} (${config.latestVersionName})',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              isMandatory
                  ? l10n.tr('force_update_msg')
                  : l10n.tr('optional_update_msg'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(notes),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (!isMandatory && onLaterPressed != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onLaterPressed,
                      child: Text(l10n.tr('later')),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: config.downloadUrl.isNotEmpty
                        ? onUpdatePressed
                        : null,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(l10n.tr('update_now')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
