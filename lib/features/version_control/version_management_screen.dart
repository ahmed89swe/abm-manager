import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/audit_log_model.dart';
import '../../providers/app_providers.dart';

class VersionManagementScreen extends ConsumerStatefulWidget {
  const VersionManagementScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<VersionManagementScreen> createState() =>
      _VersionManagementScreenState();
}

class _VersionManagementScreenState
    extends ConsumerState<VersionManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _versionNameCtrl = TextEditingController();
  final _downloadUrlCtrl = TextEditingController();
  final _notesArCtrl = TextEditingController();
  final _notesEnCtrl = TextEditingController();
  bool _isForceUpdate = false;
  bool _isSaving = false;
  bool _seeded = false;
  String _localVersion = '';

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _localVersion = info.version;
      });
    }
  }

  @override
  void dispose() {
    _versionNameCtrl.dispose();
    _downloadUrlCtrl.dispose();
    _notesArCtrl.dispose();
    _notesEnCtrl.dispose();
    super.dispose();
  }

  void _seedFromConfig(AppVersionConfig? config) {
    if (_seeded || config == null) return;
    _seeded = true;
    _versionNameCtrl.text = config.latestVersionName;
    _downloadUrlCtrl.text = config.downloadUrl;
    _notesArCtrl.text = config.releaseNotesAr;
    _notesEnCtrl.text = config.releaseNotesEn;
    _isForceUpdate = config.isForceUpdate;
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProfileProvider).value;
    if (user == null || !user.isManager) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(versionRepositoryProvider).publishNewVersion(
            manager: user,
            config: AppVersionConfig(
              latestVersionName: _versionNameCtrl.text.trim(),
              isForceUpdate: _isForceUpdate,
              downloadUrl: _downloadUrlCtrl.text.trim(),
              releaseNotesAr: _notesArCtrl.text.trim(),
              releaseNotesEn: _notesEnCtrl.text.trim(),
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).tr('success_saved')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(versionConfigProvider).value;
    _seedFromConfig(config);

    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(
                    l10n.isAr ? 'الإصدار المثبت حالياً' : 'Current App Version',
                  ),
                  subtitle:
                      Text(_localVersion.isEmpty ? '1.0.0' : _localVersion),
                  trailing: config != null
                      ? Chip(label: Text('Cloud: ${config.latestVersionName}'))
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _versionNameCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.tr('version_name'),
                          prefixIcon: const Icon(Icons.tag_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? l10n.tr('required_field')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _downloadUrlCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.tr('download_url'),
                          hintText: 'https://...',
                          prefixIcon: const Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.tr('force_update_delegates_only')),
                        subtitle: Text(l10n.tr('force_update_delegates_note')),
                        value: _isForceUpdate,
                        onChanged: (v) => setState(() => _isForceUpdate = v),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesArCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l10n.tr('release_notes_ar'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesEnCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l10n.tr('release_notes_en'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _publish,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.publish_rounded),
                        label: Text(l10n.tr('publish_version')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('version_control'))),
      body: body,
    );
  }
}
