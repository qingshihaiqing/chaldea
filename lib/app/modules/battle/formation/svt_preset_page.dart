import 'package:flutter_easyloading/flutter_easyloading.dart';

import 'package:chaldea/app/battle/models/battle.dart';
import 'package:chaldea/generated/l10n.dart';
import 'package:chaldea/models/models.dart';
import 'package:chaldea/utils/utils.dart';
import 'package:chaldea/widgets/widgets.dart';

enum _PresetFilter { all, template, currentSvt }

Future<SvtPreset?> showSaveSvtPresetDialog({
  required BuildContext context,
  required PlayerSvtData playerSvtData,
  bool defaultTemplate = true,
}) async {
  if (playerSvtData.svt == null) return null;
  final svtName = playerSvtData.dispSvt?.lName.l ?? '';
  String buildDefaultName(bool isTemplate) {
    final prefix = isTemplate ? S.current.svt_preset_template : svtName;
    final parts = <String>[
      if (prefix.isNotEmpty) prefix,
      'Lv.${playerSvtData.lv}',
      '${S.current.np_short}${playerSvtData.tdLv}',
    ];
    return parts.join(' ');
  }

  bool isTemplate = defaultTemplate;
  String lastAutoName = buildDefaultName(isTemplate);
  final controller = TextEditingController(text: lastAutoName);
  final previewPreset = playerSvtData.toPreset(name: lastAutoName, isTemplate: isTemplate);

  try {
    return await showDialog<SvtPreset>(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final trimmed = controller.text.trim();
            return AlertDialog(
              title: Text(S.current.svt_preset_save),
              scrollable: true,
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: S.current.svt_preset_name_hint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(S.current.svt_preset_template),
                          selected: isTemplate,
                          onSelected: (selected) {
                            if (!selected || isTemplate) return;
                            setDialogState(() {
                              isTemplate = true;
                              if (controller.text.trim().isEmpty || controller.text == lastAutoName) {
                                lastAutoName = buildDefaultName(true);
                                controller.text = lastAutoName;
                              }
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(S.current.svt_preset_servant_only),
                          selected: !isTemplate,
                          onSelected: (selected) {
                            if (!selected || !isTemplate) return;
                            setDialogState(() {
                              isTemplate = false;
                              if (controller.text.trim().isEmpty || controller.text == lastAutoName) {
                                lastAutoName = buildDefaultName(false);
                                controller.text = lastAutoName;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isTemplate ? S.current.svt_preset_template_desc : S.current.svt_preset_servant_only_desc,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (previewPreset != null) ...[
                      const Divider(height: 20),
                      _SvtPresetSummary(preset: previewPreset),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(S.current.cancel)),
                FilledButton(
                  onPressed: trimmed.isEmpty
                      ? null
                      : () {
                          final preset = playerSvtData.toPreset(name: trimmed, isTemplate: isTemplate);
                          if (preset == null) {
                            Navigator.pop(context);
                            return;
                          }
                          db.curUser.battleSim.svtPresets.insert(0, preset);
                          db.notifyUserdata();
                          EasyLoading.showSuccess('${S.current.saved}: $trimmed');
                          Navigator.pop(context, preset);
                        },
                  child: Text(S.current.confirm),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

class SvtPresetPage extends StatefulWidget {
  final PlayerSvtData playerSvtData;
  final Future<void> Function(SvtPreset preset, bool includeServant) onApply;

  const SvtPresetPage({super.key, required this.playerSvtData, required this.onApply});

  @override
  State<SvtPresetPage> createState() => _SvtPresetPageState();
}

class _SvtPresetPageState extends State<SvtPresetPage> {
  List<SvtPreset> get presets => db.curUser.battleSim.svtPresets;
  PlayerSvtData get playerSvtData => widget.playerSvtData;

  _PresetFilter _filter = _PresetFilter.all;
  bool _sorting = false;

  List<SvtPreset> get _filteredPresets {
    if (_sorting) return presets;
    final curSvtId = playerSvtData.svt?.id;
    return [
      for (final preset in presets)
        if (_filter == _PresetFilter.all ||
            (_filter == _PresetFilter.template && preset.isTemplate) ||
            (_filter == _PresetFilter.currentSvt && curSvtId != null && preset.data.svtId == curSvtId))
          preset,
    ];
  }

  Future<void> _saveCurrent() async {
    final created = await showSaveSvtPresetDialog(context: context, playerSvtData: playerSvtData);
    if (created != null && mounted) {
      setState(() {});
    }
  }

  Future<void> _applyPreset(SvtPreset preset, {required bool includeServant}) async {
    await widget.onApply(preset, includeServant);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _renamePreset(SvtPreset preset) {
    InputCancelOkDialog(
      title: S.current.rename,
      initValue: preset.name,
      validate: (s) => s.trim().isNotEmpty,
      onSubmit: (s) {
        if (!mounted) return;
        setState(() {
          preset.name = s.trim();
          db.notifyUserdata();
        });
      },
    ).showDialog(context);
  }

  void _toggleTemplate(SvtPreset preset) {
    setState(() {
      preset.isTemplate = !preset.isTemplate;
      db.notifyUserdata();
    });
  }

  void _overridePreset(int index, SvtPreset preset) {
    if (playerSvtData.svt == null) return;
    SimpleConfirmDialog(
      title: Text(S.current.override_),
      content: Text(preset.name),
      onTapOk: () {
        final updated = playerSvtData.toPreset(name: preset.name, isTemplate: preset.isTemplate);
        if (updated == null || !mounted) return;
        setState(() {
          presets[index] = updated;
          db.notifyUserdata();
        });
        EasyLoading.showSuccess('${S.current.saved}: ${preset.name}');
      },
    ).showDialog(context);
  }

  void _deletePreset(SvtPreset preset) {
    SimpleConfirmDialog(
      title: Text(S.current.delete),
      content: Text(preset.name),
      onTapOk: () {
        if (!mounted) return;
        setState(() {
          presets.remove(preset);
          db.notifyUserdata();
        });
      },
    ).showDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filteredPresets;
    return Scaffold(
      appBar: AppBar(
        title: Text('${S.current.svt_preset} (${presets.length})'),
        actions: [
          if (presets.length > 1)
            IconButton(
              onPressed: () {
                setState(() {
                  _sorting = !_sorting;
                });
                if (_sorting) EasyLoading.showToast(S.current.drag_to_sort);
              },
              icon: Icon(_sorting ? Icons.done : Icons.sort),
              tooltip: S.current.sort_order,
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_sorting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(S.current.general_all),
                    selected: _filter == _PresetFilter.all,
                    onSelected: (_) => setState(() => _filter = _PresetFilter.all),
                  ),
                  ChoiceChip(
                    label: Text(S.current.svt_preset_template),
                    selected: _filter == _PresetFilter.template,
                    onSelected: (_) => setState(() => _filter = _PresetFilter.template),
                  ),
                  if (playerSvtData.svt != null)
                    ChoiceChip(
                      label: Text(S.current.svt_preset_filter_current),
                      selected: _filter == _PresetFilter.currentSvt,
                      onSelected: (_) => setState(() => _filter = _PresetFilter.currentSvt),
                    ),
                ],
              ),
            ),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text(S.current.svt_preset_empty))
                : _sorting
                ? ReorderableListView(
                    children: [
                      for (int index = 0; index < presets.length; index++)
                        AbsorbPointer(
                          key: ValueKey('preset_sort_$index'),
                          child: _buildPresetCard(index, presets[index]),
                        ),
                    ],
                    onReorderItem: (int oldIndex, int newIndex) {
                      setState(() {
                        final item = presets.removeAt(oldIndex);
                        presets.insert(newIndex, item);
                        db.notifyUserdata();
                      });
                    },
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: shown.length,
                    itemBuilder: (context, idx) {
                      final preset = shown[idx];
                      final realIndex = presets.indexOf(preset);
                      return _buildPresetCard(realIndex, preset);
                    },
                  ),
          ),
          if (!_sorting && playerSvtData.svt != null) ...[
            kDefaultDivider,
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: FilledButton.tonalIcon(
                  onPressed: _saveCurrent,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(S.current.svt_preset_save),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetCard(int realIndex, SvtPreset preset) {
    final stored = preset.data;
    final presetSvt = stored.svtId == null ? null : db.gameData.servantsById[stored.svtId];
    final curSvtId = playerSvtData.svt?.id;
    final sameServant = curSvtId != null && stored.svtId == curSvtId;
    final canApplyFull = stored.svtId != null && stored.svtId != 0;
    final canApplyParams = curSvtId != null;

    Widget card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLeadingAvatar(preset, presetSvt),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(preset.name, style: Theme.of(context).textTheme.titleSmall),
                          _PresetBadge(
                            text: preset.isTemplate ? S.current.svt_preset_template : S.current.svt_preset_servant_only,
                            highlighted: preset.isTemplate,
                          ),
                          if (presetSvt != null)
                            Text(presetSvt.lName.l, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _SvtPresetSummary(preset: preset),
                    ],
                  ),
                ),
                if (!_sorting)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'rename', child: Text(S.current.rename)),
                      PopupMenuItem(value: 'toggle', child: Text(S.current.svt_preset_toggle_template)),
                      if (playerSvtData.svt != null) PopupMenuItem(value: 'override', child: Text(S.current.override_)),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(S.current.delete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    ],
                    onSelected: (action) {
                      switch (action) {
                        case 'rename':
                          _renamePreset(preset);
                        case 'toggle':
                          _toggleTemplate(preset);
                        case 'override':
                          _overridePreset(realIndex, preset);
                        case 'delete':
                          _deletePreset(preset);
                      }
                    },
                  ),
              ],
            ),
            if (!_sorting) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  if (sameServant || (canApplyParams && !canApplyFull))
                    FilledButton(
                      style: FilledButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _applyPreset(preset, includeServant: sameServant),
                      child: Text(S.current.svt_preset_apply_params),
                    )
                  else ...[
                    if (canApplyParams)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _applyPreset(preset, includeServant: false),
                        child: Text(S.current.svt_preset_apply_params),
                      ),
                    if (canApplyFull)
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _applyPreset(preset, includeServant: true),
                        child: Text(S.current.svt_preset_apply_full),
                      ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (Theme.of(context).platform.isDesktop && _sorting) {
      card = Padding(padding: const EdgeInsetsDirectional.only(end: 24), child: card);
    }
    return card;
  }

  Widget _buildLeadingAvatar(SvtPreset preset, Servant? presetSvt) {
    final Widget baseIcon;
    if (presetSvt != null) {
      baseIcon = db.getIconImage(presetSvt.ascendIcon(preset.data.limitCount), width: 48, aspectRatio: 132 / 144);
    } else {
      baseIcon = Container(
        width: 48,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.bookmarks_outlined, color: Theme.of(context).colorScheme.onSecondaryContainer),
      );
    }
    if (!preset.isTemplate) return baseIcon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        baseIcon,
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.layers, size: 12, color: Theme.of(context).colorScheme.onPrimary),
          ),
        ),
      ],
    );
  }
}

class _PresetBadge extends StatelessWidget {
  final String text;
  final bool highlighted;

  const _PresetBadge({required this.text, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlighted ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: highlighted ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SvtPresetSummary extends StatelessWidget {
  final SvtPreset preset;

  const _SvtPresetSummary({required this.preset});

  @override
  Widget build(BuildContext context) {
    final d = preset.data;
    final textStyle = Theme.of(context).textTheme.bodySmall;
    final tags = <String>[
      'Lv.${d.lv}',
      '${S.current.np_short}${d.tdLv}',
      '${S.current.bond} ${preset.bondLv}',
      'Fou +${d.atkFou}/+${d.hpFou}',
      d.skillLvs.join('/'),
      if (d.appendLvs.any((e) => e > 0)) 'AS ${d.appendLvs.map((e) => e == 0 ? '-' : '$e').join('/')}',
      if (d.cardStrengthens.any((e) => e > 0))
        '${S.current.card_strengthen} ${d.cardStrengthens.every((e) => e == d.cardStrengthens.first) ? '+${d.cardStrengthens.first}' : d.cardStrengthens.join('/')}',
      if (d.grandSvt) S.current.grand_servant,
      if (d.classBoardData?.classBoardSquares.isNotEmpty == true)
        '${S.current.class_board} ${d.classBoardData!.classBoardSquares.length}',
      if (d.grandSvt && d.classBoardData?.grandClassBoardSquares.isNotEmpty == true)
        'Grand ${d.classBoardData!.grandClassBoardSquares.length}',
      if (d.customPassives.isNotEmpty) 'Buff ×${d.customPassives.length}',
    ];

    final codes = <CommandCode?>[for (final id in d.commandCodeIds) db.gameData.commandCodesById[id]];
    final hasAnyCode = codes.any((e) => e != null);
    final ce1 = d.equip1.id == null ? null : db.gameData.craftEssencesById[d.equip1.id];
    final ce2 = d.grandSvt && d.equip2?.id != null ? db.gameData.craftEssencesById[d.equip2!.id] : null;
    final ce3 = d.grandSvt && d.equip3?.id != null ? db.gameData.craftEssencesById[d.equip3!.id] : null;
    final equips = <(CraftEssence, SvtEquipSaveData)>[
      if (ce1 != null) (ce1, d.equip1),
      if (ce2 != null && d.equip2 != null) (ce2, d.equip2!),
      if (ce3 != null && d.equip3 != null) (ce3, d.equip3!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tags.join(' · '), style: textStyle),
        if (hasAnyCode || equips.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hasAnyCode)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final code in codes)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: db.getIconImage(
                          code?.icon ?? Atlas.asset('SkillIcons/skill_999999.png'),
                          height: 24,
                          aspectRatio: 132 / 144,
                        ),
                      ),
                  ],
                ),
              for (final (ce, equipData) in equips)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    db.getIconImage(ce.borderedIcon, height: 24),
                    const SizedBox(width: 4),
                    Text(
                      '${ce.lName.l} Lv.${equipData.lv}${equipData.limitBreak ? ' ${S.current.max_limit_break}' : ''}',
                      style: textStyle,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
