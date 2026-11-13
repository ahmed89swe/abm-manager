import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/utils/formatters.dart';
import '../../models/master_data_models.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common_widgets.dart';

class MasterDataScreen extends ConsumerStatefulWidget {
  const MasterDataScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<MasterDataScreen> createState() => _MasterDataScreenState();
}

class _MasterDataScreenState extends ConsumerState<MasterDataScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final governorates = ref.watch(governoratesProvider).value ?? const [];
    final materials = ref.watch(materialsProvider).value ?? const [];

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(l10n.tr('master_data')),
              bottom: TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: l10n.tr('governorates')),
                  Tab(text: l10n.tr('materials')),
                ],
              ),
            ),
      body: ResponsivePageContainer(
        maxWidth: 1160,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 680;
                  final searchBox = TextField(
                    decoration: InputDecoration(
                      hintText: l10n.tr('search'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  );
                  final sectionSwitch = SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.location_city_outlined),
                        label: Text(l10n.tr('governorates')),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.medication_outlined),
                        label: Text(l10n.tr('materials')),
                      ),
                    ],
                    selected: {_tabController.index},
                    onSelectionChanged: (s) =>
                        _tabController.animateTo(s.first),
                  );

                  if (widget.embedded) {
                    return wide
                        ? Row(
                            children: [
                              sectionSwitch,
                              const SizedBox(width: 14),
                              Expanded(child: searchBox),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              sectionSwitch,
                              const SizedBox(height: 10),
                              searchBox,
                            ],
                          );
                  }
                  return searchBox;
                },
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGovernoratesList(governorates, l10n),
                  _buildMaterialsList(materials, l10n),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _openGovernorateDialog();
          } else {
            _openMaterialDialog();
          }
        },
        icon: const Icon(Icons.add),
        label: Text(
          _tabController.index == 0
              ? l10n.tr('governorate')
              : l10n.tr('material'),
        ),
      ),
    );
  }

  Widget _buildGovernoratesList(
      List<Governorate> list, AppLocalizations l10n) {
    final filtered = list
        .where((e) =>
            e.nameAr.toLowerCase().contains(_search) ||
            e.nameEn.toLowerCase().contains(_search))
        .toList();
    if (filtered.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.map_outlined,
        message: l10n.tr('no_data'),
      );
    }
    return SingleChildScrollView(
      padding: ResponsiveBreakpoints.pagePadding(context, withFab: true),
      child: ResponsiveCardGrid(
        children: filtered
            .map(
              (g) => Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.location_city)),
                  title: Text(
                    g.nameAr,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: g.nameEn.isNotEmpty ? Text(g.nameEn) : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openGovernorateDialog(existing: g),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildMaterialsList(
      List<MaterialEntity> list, AppLocalizations l10n) {
    final filtered =
        list.where((e) => e.name.toLowerCase().contains(_search)).toList();
    if (filtered.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.medication_outlined,
        message: l10n.tr('no_data'),
      );
    }
    return SingleChildScrollView(
      padding: ResponsiveBreakpoints.pagePadding(context, withFab: true),
      child: ResponsiveCardGrid(
        children: filtered
            .map(
              (m) => Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.medication_liquid)),
                  title: Text(
                    m.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    m.defaultUnitPrice != null
                        ? '${m.unit} • ${AppFormatters.formatMoney(m.defaultUnitPrice!, currency: l10n.tr('currency'))}'
                        : m.unit,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openMaterialDialog(existing: m),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _openGovernorateDialog({Governorate? existing}) {
    final l10n = AppLocalizations.of(context);
    final arCtrl = TextEditingController(text: existing?.nameAr ?? '');
    final enCtrl = TextEditingController(text: existing?.nameEn ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('governorate')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 440),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: arCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.isAr ? 'الاسم بالعربية' : 'Arabic Name',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.tr('required_field')
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: enCtrl,
                    decoration: InputDecoration(
                      labelText:
                          l10n.isAr ? 'الاسم بالإنجليزية' : 'English Name',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final actor = ref.read(currentUserProfileProvider).value;
              if (actor == null) return;
              await ref.read(masterDataRepositoryProvider).saveDocument(
                    actor: actor,
                    collection: 'governorates',
                    docId: existing?.id,
                    data: Governorate(
                      id: existing?.id ?? '',
                      nameAr: arCtrl.text.trim(),
                      nameEn: enCtrl.text.trim(),
                    ).toMap(),
                    entityLabelAr: 'محافظة ${arCtrl.text.trim()}',
                    entityLabelEn: 'Governorate ${arCtrl.text.trim()}',
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(l10n.tr('save')),
          ),
        ],
      ),
    );
  }

  void _openMaterialDialog({MaterialEntity? existing}) {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
      text: existing?.defaultUnitPrice?.toString() ?? '',
    );
    final unitCtrl = TextEditingController(text: existing?.unit ?? 'علبة');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('material')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 440),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.isAr ? 'اسم المادة' : 'Material Name',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.tr('required_field')
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.isAr
                          ? 'سعر المفرد الافتراضي (اختياري)'
                          : 'Default Unit Price (Optional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: unitCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.isAr ? 'الوحدة' : 'Unit',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final actor = ref.read(currentUserProfileProvider).value;
              if (actor == null) return;
              final price = double.tryParse(priceCtrl.text.trim());
              await ref.read(masterDataRepositoryProvider).saveDocument(
                    actor: actor,
                    collection: 'materials',
                    docId: existing?.id,
                    data: MaterialEntity(
                      id: existing?.id ?? '',
                      name: nameCtrl.text.trim(),
                      defaultUnitPrice: price,
                      unit: unitCtrl.text.trim().isEmpty
                          ? 'علبة'
                          : unitCtrl.text.trim(),
                    ).toMap(),
                    entityLabelAr: 'مادة ${nameCtrl.text.trim()}',
                    entityLabelEn: 'Material ${nameCtrl.text.trim()}',
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(l10n.tr('save')),
          ),
        ],
      ),
    );
  }
}
