/// First launch (and after signing out): sign in to an account, or create one. The same username
/// and password work on every device; the device keeps a session token, not the password.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../net/account.dart';
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
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _create = false;
  bool _busy = false;
  bool _showPass = false;
  String? _userError, _passError, _formError;
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
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ue = usernameError(_user.text);
    final pe = _create ? passwordError(_pass.text, username: _user.text) : (_pass.text.isEmpty ? 'Enter your password.' : null);
    setState(() {
      _userError = ue;
      _passError = pe;
      _formError = null;
    });
    if (ue != null || pe != null) return;
    setState(() => _busy = true);
    try {
      final a = AccountService();
      final r = _create ? await a.register(_user.text, _pass.text) : await a.signIn(_user.text, _pass.text);
      if (!mounted) return;
      context.services.settings.update((x) => x
        ..username = r.username
        ..accountToken = r.token);
      await Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, _, _) => const MenuScreen(),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        ),
      );
    } catch (e) {
      final msg = e is StateError ? e.message : 'Something went wrong. Try again.';
      if (!mounted) return;
      setState(() {
        // Name problems go under the username, password problems under the password, the rest
        // (wrong password, no connection) under the button.
        if (msg.contains('username is taken') || msg.contains('Usernames are')) {
          _userError = msg;
        } else if (msg.contains('Passwords are') || msg.contains("can't be the same")) {
          _passError = msg;
        } else {
          _formError = msg;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _mode(bool create) {
    if (create == _create) return;
    setState(() {
      _create = create;
      _userError = _passError = _formError = null;
    });
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
                      child: AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _create ? 'CLAIM YOUR\nNAME' : 'WHO STEPS INTO\nTHE ARENA?',
                              style: titleStyle((size.height * 0.075).clamp(24, 44), spacing: 1.5),
                            ),
                            const SizedBox(height: 6),
                            const DecoRule(width: 200, opacity: 0.4),
                            const SizedBox(height: 14),
                            _Tabs(create: _create, onChanged: _busy ? null : _mode),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _user,
                              autofocus: !kIsWeb,
                              enabled: !_busy,
                              maxLength: maxNameLength,
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: [_create ? AutofillHints.newUsername : AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _passFocus.requestFocus(),
                              onChanged: (_) {
                                if (_userError != null || _formError != null) setState(() => _userError = _formError = null);
                              },
                              style: titleStyle(22, weight: FontWeight.w700, spacing: 0.6),
                              decoration: nameFieldDecoration(_userError).copyWith(
                                hintText: 'Username',
                                prefixIcon: const Icon(Icons.person_rounded, color: Palette.boneDim),
                                helperText: _create ? 'Letters, numbers and _ · goes on your name plate' : null,
                                helperStyle: bodyStyle(12.5, color: Palette.muted),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _pass,
                              focusNode: _passFocus,
                              enabled: !_busy,
                              obscureText: !_showPass,
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              onChanged: (_) {
                                if (_passError != null || _formError != null) setState(() => _passError = _formError = null);
                              },
                              style: titleStyle(22, weight: FontWeight.w700, spacing: 0.6),
                              decoration: nameFieldDecoration(_passError).copyWith(
                                hintText: 'Password',
                                counterText: '',
                                prefixIcon: const Icon(Icons.lock_rounded, color: Palette.boneDim),
                                suffixIcon: IconButton(
                                  tooltip: _showPass ? 'Hide password' : 'Show password',
                                  icon: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Palette.boneDim),
                                  onPressed: () => setState(() => _showPass = !_showPass),
                                ),
                                helperText: _create ? 'At least 6 characters' : null,
                                helperStyle: bodyStyle(12.5, color: Palette.muted),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                PlateButton(
                                  label: _busy ? (_create ? 'Creating…' : 'Signing in…') : (_create ? 'Create account' : 'Sign in'),
                                  icon: _create ? Icons.person_add_alt_1_rounded : Icons.login_rounded,
                                  width: 260,
                                  onPressed: _busy ? null : _submit,
                                ),
                                if (_busy) ...[
                                  const SizedBox(width: 14),
                                  const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Palette.boneDim),
                                  ),
                                ],
                              ],
                            ),
                            if (_formError != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error_outline_rounded, size: 18, color: Palette.danger),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(_formError!, style: bodyStyle(14, color: Palette.danger))),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              _create
                                  ? 'One account for your phone, PC and the web. Names are unique: nobody else can take yours.'
                                  : 'The same account works on every device.',
                              style: bodyStyle(13.5, color: Palette.boneDim),
                            ),
                          ],
                        ),
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

/// SIGN IN | CREATE ACCOUNT: two cut plates, the chosen one filled bone.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.create, required this.onChanged});
  final bool create;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (label, value) in const [('SIGN IN', false), ('CREATE ACCOUNT', true)])
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Semantics(
            button: true,
            selected: create == value,
            child: InkWell(
              onTap: onChanged == null ? null : () => onChanged!(value),
              customBorder: const ChamferBorder(cut: 7),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: create == value ? Palette.bone : const Color(0xCC0A0D13),
                  shape: ChamferBorder(cut: 7, side: BorderSide(color: Palette.bone.withValues(alpha: create == value ? 1 : 0.35))),
                ),
                child: Text(label, style: titleStyle(15, color: create == value ? Palette.bgDeep : Palette.boneDim, spacing: 1.2)),
              ),
            ),
          ),
        ),
    ],
  );
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
