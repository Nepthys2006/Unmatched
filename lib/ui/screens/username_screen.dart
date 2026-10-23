/// First launch: the player names themselves. Saved on the device.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'menu_screen.dart';

const maxNameLength = 16;

/// Trims and validates a player name. Returns an error message, or null when it is fine.
String? nameError(String raw) {
  final n = raw.trim();
  if (n.isEmpty) return 'Enter a name to continue.';
  if (n.length > maxNameLength) return 'Keep it to $maxNameLength characters.';
  return null;
}

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});
  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _field = TextEditingController();
  String? _error;
  String? _mini;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.services;
    if (_mini == null && s.loaded) {
      final heroes = s.data.heroes.values.toList();
      _mini = heroes[math.Random().nextInt(heroes.length)].mini;
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final err = nameError(_field.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final s = context.services;
    s.settings.update((x) => x.username = _field.text.trim());
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => const MenuScreen(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: TableBackground(
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: _mini == null
                    ? const SizedBox()
                    : Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Positioned(
                            bottom: size.height * 0.08,
                            child: Container(
                              width: size.height * 0.6,
                              height: size.height * 0.1,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(Radius.elliptical(size.height * 0.3, size.height * 0.05)),
                                gradient: RadialGradient(colors: [Palette.bone.withValues(alpha: 0.18), Colors.transparent]),
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(bottom: size.height * 0.1, top: size.height * 0.08),
                            child: Image.asset(_mini!, fit: BoxFit.contain),
                          ),
                        ],
                      ),
              ),
              Expanded(
                flex: 6,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 40, 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WHO STEPS INTO\nTHE ARENA?', style: titleStyle((size.height * 0.085).clamp(26, 48), spacing: 1.5)),
                          const SizedBox(height: 6),
                          const DecoRule(width: 200, opacity: 0.4),
                          const SizedBox(height: 14),
                          Text('Your name goes on your name plate in every match.', style: bodyStyle(15, color: Palette.boneDim)),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _field,
                            autofocus: true,
                            maxLength: maxNameLength,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            onChanged: (_) {
                              if (_error != null) setState(() => _error = null);
                            },
                            style: titleStyle(24, weight: FontWeight.w700, spacing: 0.6),
                            decoration: nameFieldDecoration(_error),
                          ),
                          const SizedBox(height: 14),
                          PlateButton(label: 'Continue', icon: Icons.arrow_forward_rounded, width: 220, onPressed: _submit),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chamfered name input used here and in Settings.
InputDecoration nameFieldDecoration(String? error) => InputDecoration(
  hintText: 'Your name',
  hintStyle: titleStyle(24, color: Palette.muted, weight: FontWeight.w600, spacing: 0.6),
  errorText: error,
  errorStyle: bodyStyle(13, color: Palette.danger),
  counterStyle: bodyStyle(12, color: Palette.muted),
  filled: true,
  fillColor: Palette.bgDeep,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  border: ChamferInputBorder(color: Palette.bone.withValues(alpha: 0.3)),
  enabledBorder: ChamferInputBorder(color: Palette.bone.withValues(alpha: 0.3)),
  focusedBorder: const ChamferInputBorder(color: Palette.bone, width: 1.6),
  errorBorder: const ChamferInputBorder(color: Palette.danger),
  focusedErrorBorder: const ChamferInputBorder(color: Palette.danger, width: 1.6),
);

/// An input border with cut corners, matching the panels.
class ChamferInputBorder extends InputBorder {
  const ChamferInputBorder({this.color = Palette.line, this.width = 1}) : super(borderSide: BorderSide.none);
  final Color color;
  final double width;

  @override
  bool get isOutline => true;
  @override
  ChamferInputBorder copyWith({BorderSide? borderSide}) =>
      ChamferInputBorder(color: borderSide?.color ?? color, width: borderSide?.width ?? width);
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => const ChamferBorder(cut: 9).pathFor(rect.deflate(width));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => const ChamferBorder(cut: 9).pathFor(rect);
  @override
  void paint(Canvas canvas, Rect rect, {double? gapStart, double gapExtent = 0, double gapPercentage = 0, TextDirection? textDirection}) {
    canvas.drawPath(
      const ChamferBorder(cut: 9).pathFor(rect.deflate(width / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  ShapeBorder scale(double t) => ChamferInputBorder(color: color, width: width * t);
}
