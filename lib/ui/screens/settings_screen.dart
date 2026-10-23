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
                  Quality.low => 'Flat orbs, no camera moves',
                  Quality.medium => 'Glow and camera push-in',
                  Quality.high => 'Everything, plus sparks',
                },
                selected: s.quality == q,
                height: 62,
                onTap: () => s.update((x) => x.quality = q),
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
    ],
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
