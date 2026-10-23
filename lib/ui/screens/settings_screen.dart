/// Settings: name, graphics quality, animation speed, volumes, confirmations.
library;

import 'package:flutter/material.dart';

import '../audio.dart';
import '../board3d/board3d.dart';
import '../services.dart';
import '../settings.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'username_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.inMatch = false});

  /// Opened from the pause menu: the name can't change mid-match.
  final bool inMatch;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _name = TextEditingController(text: context.services.settings.username);
  String? _nameError;

  @override
  void dispose() {
    _saveName();
    _name.dispose();
    super.dispose();
  }

  void _saveName() {
    if (widget.inMatch) return;
    final s = context.services.settings;
    if (nameError(_name.text) == null && _name.text.trim() != s.username) s.update((x) => x.username = _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.services.settings;
    return Scaffold(
      body: TableBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: s,
            builder: (context, _) => Column(
              children: [
                const ScreenHeader(title: 'Settings'),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final wide = c.maxWidth > 760;
                      final left = _leftColumn(s);
                      final right = _rightColumn(s);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1040),
                            child: wide
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: left),
                                      const SizedBox(width: 28),
                                      Expanded(child: right),
                                    ],
                                  )
                                : Column(children: [left, const SizedBox(height: 20), right]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _leftColumn(Settings s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionLabel('Player'),
      TextField(
        controller: _name,
        enabled: !widget.inMatch,
        maxLength: maxNameLength,
        textCapitalization: TextCapitalization.words,
        onChanged: (v) => setState(() => _nameError = nameError(v)),
        onSubmitted: (_) => _saveName(),
        style: titleStyle(22, weight: FontWeight.w700, spacing: 0.6),
        decoration: nameFieldDecoration(_nameError),
      ),
      const SizedBox(height: 14),
      const SectionLabel('Graphics'),
      Row(
        children: [
          for (final q in Quality.values) ...[
            Expanded(
              child: ChoiceTile(
                label: q.label,
                sub: switch (q) {
                  Quality.low => 'Fastest',
                  Quality.medium => 'Phones',
                  Quality.high => 'Most PCs',
                  Quality.ultra => 'Strong GPUs',
                },
                selected: s.quality == q,
                height: 62,
                onTap: () => s.update((x) => x.applyPreset(q)),
              ),
            ),
            if (q != Quality.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
      const SizedBox(height: 18),
      const SectionLabel('Battlefield'),
      Row(
        children: [
          Expanded(
            child: ChoiceTile(
              label: '3D map',
              sub: board3dSupported ? 'The 3D table models' : 'Not available on this device',
              selected: s.board3d && board3dSupported,
              height: 62,
              onTap: board3dSupported ? () => s.update((x) => x.board3d = true) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ChoiceTile(
              label: 'Flat 2D',
              sub: 'Fastest, works everywhere',
              selected: !s.board3d || !board3dSupported,
              height: 62,
              onTap: () => s.update((x) => x.board3d = false),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      const SectionLabel('Animation speed'),
      Row(
        children: [
          for (final a in AnimSpeed.values) ...[
            Expanded(
              child: ChoiceTile(label: a.label, selected: s.animSpeed == a, onTap: () => s.update((x) => x.animSpeed = a)),
            ),
            if (a != AnimSpeed.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    ],
  );

  Widget _rightColumn(Settings s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionLabel('Sound'),
      _VolumeRow(
        label: 'Music',
        icon: Icons.music_note_rounded,
        value: s.musicVolume,
        onChanged: (v) => s.update((x) => x.musicVolume = v),
      ),
      _VolumeRow(
        label: 'Effects',
        icon: Icons.graphic_eq_rounded,
        value: s.sfxVolume,
        onChanged: (v) => s.update((x) => x.sfxVolume = v),
        onChangeEnd: (_) => context.services.audio.sfx(Sfx.hit),
      ),
      const SizedBox(height: 14),
      const SectionLabel('Gameplay'),
      Panel(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ASK BEFORE COMMITTING', style: titleStyle(16)),
                  const SizedBox(height: 2),
                  Text('"Are you sure?" before you attack. Everything else happens on the first tap.', style: bodyStyle(13, color: Palette.muted)),
                ],
              ),
            ),
            Switch(value: s.confirmActions, onChanged: (v) => s.update((x) => x.confirmActions = v)),
          ],
        ),
      ),
      if (board3dSupported) ...[const SizedBox(height: 14), ..._graphics3d(s)],
    ],
  );

  /// Fine control over the 3D map. The quality preset sets these; changes apply at once, even
  /// mid-match (antialiasing restarts the 3D view).
  List<Widget> _graphics3d(Settings s) => [
    const SectionLabel('3D map graphics'),
    _SliderRow(
      label: 'Resolution',
      icon: Icons.high_quality_rounded,
      value: s.renderScale,
      min: 0.5,
      max: 1.5,
      divisions: 20,
      format: (v) => '${(v * 100).round()}%',
      onChanged: (v) => s.update((x) => x.renderScale = v),
    ),
    _SwitchRow(
      label: 'Keep it smooth',
      sub: 'Lowers the resolution by itself if the frame rate drops',
      value: s.autoResolution,
      onChanged: (v) => s.update((x) => x.autoResolution = v),
    ),
    const SizedBox(height: 6),
    Text('SHADOWS', style: titleStyle(14, color: Palette.boneDim, spacing: 1.4)),
    const SizedBox(height: 6),
    Row(
      children: [
        for (final sh in Shadows.values) ...[
          Expanded(
            child: ChoiceTile(label: sh.label, selected: s.shadows == sh, height: 44, onTap: () => s.update((x) => x.shadows = sh)),
          ),
          if (sh != Shadows.values.last) const SizedBox(width: 6),
        ],
      ],
    ),
    const SizedBox(height: 6),
    _SwitchRow(
      label: 'Anti-aliasing',
      sub: 'Smooth edges',
      value: s.antialias,
      onChanged: (v) => s.update((x) => x.antialias = v),
    ),
    _SwitchRow(
      label: 'Glow',
      sub: 'Bloom on the orbs and bright spots',
      value: s.bloom,
      onChanged: (v) => s.update((x) => x.bloom = v),
    ),
    _SwitchRow(
      label: 'Ambient occlusion',
      sub: 'Soft shading in corners and under objects (costly)',
      value: s.ambientOcclusion,
      onChanged: (v) => s.update((x) => x.ambientOcclusion = v),
    ),
    _SwitchRow(
      label: 'Scenery',
      sub: 'Trees, rocks and buildings around the spaces',
      value: s.scenery,
      onChanged: (v) => s.update((x) => x.scenery = v),
    ),
    _SliderRow(
      label: 'Brightness',
      icon: Icons.brightness_6_rounded,
      value: s.brightness,
      min: 0.6,
      max: 1.6,
      divisions: 20,
      format: (v) => '${(v * 100).round()}%',
      onChanged: (v) => s.update((x) => x.brightness = v),
    ),
    _SliderRow(
      label: 'Name size',
      icon: Icons.text_fields_rounded,
      value: s.labelSize,
      min: 0.6,
      max: 1.8,
      divisions: 12,
      format: (v) => '${(v * 100).round()}%',
      onChanged: (v) => s.update((x) => x.labelSize = v),
    ),
    _SwitchRow(
      label: 'Show FPS',
      sub: 'Frames per second on the 3D map',
      value: s.showFps,
      onChanged: (v) => s.update((x) => x.showFps = v),
    ),
  ];
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, required this.sub, required this.value, required this.onChanged});
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: titleStyle(15)),
              Text(sub, style: bodyStyle(12.5, color: Palette.muted)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    child: Row(
      children: [
        Icon(icon, color: Palette.boneDim, size: 20),
        const SizedBox(width: 10),
        SizedBox(width: 104, child: Text(label.toUpperCase(), style: titleStyle(15))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            semanticFormatterCallback: (v) => '$label ${format(v)}',
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(format(value), textAlign: TextAlign.right, style: titleStyle(15, color: Palette.boneDim, weight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.label, required this.icon, required this.value, required this.onChanged, this.onChangeEnd});
  final String label;
  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: Row(
      children: [
        Icon(icon, color: Palette.boneDim, size: 22),
        const SizedBox(width: 10),
        SizedBox(width: 74, child: Text(label.toUpperCase(), style: titleStyle(16))),
        Expanded(
          child: Slider(
            value: value,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
            semanticFormatterCallback: (v) => '$label ${(v * 100).round()} percent',
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).round()}',
            textAlign: TextAlign.right,
            style: titleStyle(16, color: Palette.boneDim, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
