import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/providers/app_preferences_provider.dart';
import '../../main.dart';
import '../../models/app_user.dart';
import '../../providers/app_providers.dart';
import '../../services/receipt_storage_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/user_avatar_widget.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _seeded = false;
  bool _savingProfile = false;
  PickedImageData? _pendingAvatarImage;
  String? _pendingAvatarBase64;
  bool _removeAvatar = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _seedUser(AppUser user) {
    if (_seeded) return;
    _seeded = true;
    _nameCtrl.text = user.name;
    _phoneCtrl.text = user.phone;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked =
        await ReceiptStorageService.instance.pickAvatar(source: source);
    if (picked != null && mounted) {
      setState(() {
        _pendingAvatarImage = picked.image;
        _pendingAvatarBase64 = picked.base64;
        _removeAvatar = false;
      });
    }
  }

  void _showPhotoPickerSheet(AppLocalizations l10n, AppUser user) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.camera_alt_outlined),
                    title: Text(l10n.tr('camera')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickPhoto(ImageSource.camera);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(l10n.tr('gallery')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickPhoto(ImageSource.gallery);
                  },
                ),
                if (user.avatarBytes != null ||
                    (user.photoUrl != null && user.photoUrl!.isNotEmpty) ||
                    _pendingAvatarBase64 != null)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                    title: Text(
                      l10n.tr('remove_photo'),
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _pendingAvatarImage = null;
                        _pendingAvatarBase64 = '';
                        _removeAvatar = true;
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile(AppUser user, AppLocalizations l10n) async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('required_field'))),
      );
      return;
    }
    setState(() => _savingProfile = true);
    try {
      await ref.read(authRepositoryProvider).updateProfile(
            user: user,
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            avatarBase64:
                _removeAvatar ? '' : (_pendingAvatarBase64 ?? user.avatarBase64),
            avatarImage: _removeAvatar ? null : _pendingAvatarImage,
          );
      if (mounted) {
        setState(() {
          _pendingAvatarImage = null;
          _pendingAvatarBase64 = null;
          _removeAvatar = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('success_saved'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _signOut() async {
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(appPreferencesProvider);
    final user = ref.watch(currentUserProfileProvider).value;
    if (user != null) {
      _seedUser(user);
    }

    final profileCard = user == null
        ? const SizedBox.shrink()
        : Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          if (_removeAvatar)
                            CircleAvatar(
                              radius: 36,
                              child: Icon(
                                user.isManager
                                    ? Icons.admin_panel_settings
                                    : Icons.person_outline,
                                size: 32,
                              ),
                            )
                          else if (_pendingAvatarBase64 != null &&
                              _pendingAvatarBase64!.isNotEmpty)
                            CircleAvatar(
                              radius: 36,
                              backgroundImage: MemoryImage(
                                base64Decode(_pendingAvatarBase64!),
                              ),
                            )
                          else
                            UserAvatarWidget(user: user, radius: 36),
                          Material(
                            shape: const CircleBorder(),
                            color: Theme.of(context).colorScheme.primary,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _showPhotoPickerSheet(l10n, user),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.camera_alt_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${user.email}${user.governorateName != null ? " • ${user.governorateName}" : ""}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                user.isManager
                                    ? (l10n.isAr ? 'مدير النظام' : 'Manager')
                                    : (l10n.isAr ? 'مندوب' : 'Delegate'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Text(
                    l10n.tr('profile'),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.tr('personal_name'),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l10n.tr('phone'),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showPhotoPickerSheet(l10n, user),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(l10n.tr('change_photo')),
                      ),
                      FilledButton.icon(
                        onPressed: _savingProfile
                            ? null
                            : () => _saveProfile(user, l10n),
                        icon: _savingProfile
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(l10n.tr('save_profile')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

    final preferencesCard = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.translate_rounded),
                        const SizedBox(width: 12),
                        Text(
                          l10n.tr('language'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'ar',
                            label: Text(l10n.tr('arabic')),
                          ),
                          ButtonSegment(
                            value: 'en',
                            label: Text(l10n.tr('english')),
                          ),
                        ],
                        selected: {prefs.locale.languageCode},
                        onSelectionChanged: (s) {
                          ref
                              .read(appPreferencesProvider.notifier)
                              .setLanguage(s.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.palette_outlined),
                        const SizedBox(width: 12),
                        Text(
                          l10n.tr('theme_mode'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: const Icon(Icons.light_mode_outlined),
                            label: Text(l10n.tr('light_mode')),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: const Icon(Icons.dark_mode_outlined),
                            label: Text(l10n.tr('dark_mode')),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: const Icon(Icons.brightness_auto_outlined),
                            label: Text(l10n.tr('system_mode')),
                          ),
                        ],
                        selected: {prefs.themeMode},
                        onSelectionChanged: (s) {
                          ref
                              .read(appPreferencesProvider.notifier)
                              .setThemeMode(s.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(color: Theme.of(context).colorScheme.error),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: _signOut,
          icon: const Icon(Icons.logout_rounded),
          label: Text(l10n.tr('logout')),
        ),
      ],
    );

    final body = ResponsivePageContainer(
      maxWidth: 1120,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoCol = constraints.maxWidth >= 820 && user != null;
          return SingleChildScrollView(
            padding: ResponsiveBreakpoints.pagePadding(context),
            child: twoCol
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: profileCard),
                      const SizedBox(width: 20),
                      Expanded(flex: 5, child: preferencesCard),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (user != null) ...[
                        profileCard,
                        const SizedBox(height: 16),
                      ],
                      preferencesCard,
                    ],
                  ),
          );
        },
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('settings'))),
      body: body,
    );
  }
}
