/// Keeps the text field you are typing in above the on-screen keyboard without resizing anything.
///
/// The screens that use it set `resizeToAvoidBottomInset: false` (the keyboard is drawn over them,
/// nothing is squeezed) and give their scroll view a bottom padding as tall as the keyboard. This
/// widget, placed inside that scroll view, scrolls the focused field to the middle of the part of
/// the screen the keyboard leaves free, whenever focus moves or the keyboard opens, grows or closes.
library;

import 'dart:async';

import 'package:flutter/material.dart';

class KeepFocusVisible extends StatefulWidget {
  const KeepFocusVisible({super.key, required this.child});
  final Widget child;

  @override
  State<KeepFocusVisible> createState() => _KeepFocusVisibleState();
}

class _KeepFocusVisibleState extends State<KeepFocusVisible>
    with WidgetsBindingObserver {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_schedule);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    FocusManager.instance.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _schedule();

  /// Metrics change many times while the keyboard slides: act once it has settled a little.
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _reveal);
  }

  void _reveal() {
    if (!mounted) return;
    final focus = FocusManager.instance.primaryFocus;
    final field = focus?.context;
    if (field == null || !field.mounted) return;
    // Only fields of this screen's scroll view.
    if (context.findAncestorStateOfType<ScrollableState>() == null) return;
    final mine = field.findAncestorStateOfType<_KeepFocusVisibleState>();
    if (mine != this) return;
    final scrollable = Scrollable.maybeOf(field);
    final fieldBox = field.findRenderObject();
    final viewBox = scrollable?.context.findRenderObject();
    if (scrollable == null ||
        fieldBox is! RenderBox ||
        viewBox is! RenderBox ||
        !fieldBox.attached ||
        !viewBox.attached) {
      return;
    }
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // No keyboard (a desktop, a hardware keyboard): nothing to avoid, leave the scroll alone.
    if (keyboard <= 0) return;
    final viewH = viewBox.size.height;
    final fieldH = fieldBox.size.height;
    // Where the field goes: the middle of the area above the keyboard.
    final target = ((viewH - keyboard - fieldH) / 2).clamp(
      0.0,
      double.infinity,
    );
    final span = viewH - fieldH;
    final alignment = span <= 0 ? 0.0 : (target / span).clamp(0.0, 1.0);
    unawaited(
      Scrollable.ensureVisible(
        field,
        alignment: alignment,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
