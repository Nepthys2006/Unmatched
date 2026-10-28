/// The live match: runs the engine, paces its events into animations, and turns every prompt
/// the player must answer into highlights, a card choice or a panel.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart' hide Card, Intent;

import '../../engine/ai.dart';
import '../../engine/combat.dart';
import '../../engine/defs.dart' show MapArt;
import '../../engine/events.dart';
import '../../engine/game.dart';
import '../../engine/hero_script.dart' show FighterPlacedAtStart;
import '../../engine/portable_random.dart';
import '../../engine/prompt.dart';
import '../../engine/state.dart';
import '../audio.dart';
import '../platform/fullscreen.dart';
import '../board/board_painter.dart';
import '../board3d/board3d.dart';
import '../../net/session.dart';
import '../screens/settings_screen.dart';
import '../settings.dart';
import '../services.dart';
import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agents.dart';
import 'board_layer.dart';
import 'figure_art.dart';
import 'hero_items.dart';
import 'hud.dart';
import 'match_config.dart';
import 'plate_parts.dart';

/// Dev-only: `--dart-define=AUTOPLAY=true` lets an AI answer your prompts (after showing them)
/// so whole matches can be screenshot and soak-tested. Never set in real builds.
const _autoplay = bool.fromEnvironment('AUTOPLAY');

class _Abandoned implements Exception {
  const _Abandoned();
}

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.config, this.seed, this.autoplay = _autoplay, this.net});

  /// LAN / online: who sits where and how decisions travel. Null for a game against the AI.
  final NetMatch? net;
  final MatchConfig config;

  /// An AI answers your prompts too (dev builds and tests only).
  final bool autoplay;

  /// Tests only: a fixed shuffle. Real games shuffle with Random.secure().
  final int? seed;

  @override
  State<MatchScreen> createState() => MatchScreenState();
}

class MatchScreenState extends State<MatchScreen> with TickerProviderStateMixin {
  late final Services _s = context.services;
  late Game game;
  late BoardGeometry geo;
  Player get me => game.players[widget.net?.localSeat ?? 0];

  // Prompt state.
  Prompt? _prompt;
  Completer<List<int>>? _answer;
  bool _attackMode = false;
  Fighter? _attackTarget;
  bool _schemeHint = false;
  final BoardMarks _marks = BoardMarks();
  Player? _thinking;

  // Presentation state.
  final List<LogLine> _log = [];
  bool _showLog = false;
  Combat? _combat;
  bool _revealed = false;
  bool _resolved = false;
  Side? _resolving;
  String? _effectText;
  (Card, String)? _spot;

  /// Cards shown to you (a hand you look at, cards revealed to everyone) until you tap OK.
  ({String title, List<Card> cards, bool private})? _reveal;
  Completer<void>? _revealDone;
  GameOver? _result;
  String _bannerTitle = '';
  String _bannerSub = '';
  Color _bannerColor = Palette.bone;
  String? _error;
  bool _started = false;
  bool _disposed = false;

  /// The camera controls dropdown is open.
  bool _camOpen = false;

  // Animation.
  final SteppedPulse _pulse = SteppedPulse();
  late final AnimationController _banner = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final AnimationController _moveA = AnimationController(vsync: this);
  late final AnimationController _fxA = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  late final AnimationController _camA = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _shakeA = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  final ValueNotifier<MoveAnim?> _move = ValueNotifier(null);
  final ValueNotifier<int> _boardTick = ValueNotifier(0);
  final List<Fx> _fx = [];
  final TransformationController _cam = TransformationController();

  /// Device pixels per board unit at the camera's zoom, in quarter-octave steps: it picks each
  /// picture's filter (enlarged: bicubic, shrunk: mipmapped), and only changes, so repaints, when
  /// the zoom crosses a step rather than on every frame of a pan or pinch.
  final ValueNotifier<double> _pxPerUnit = ValueNotifier(1);
  double _dpr = 1;
  Matrix4? _camHome;

  /// The 2D board's own box (inside the camera's transform), for [debugSpaceOnScreen].
  final GlobalKey _boardKey = GlobalKey();

  /// Tests: where space [id] is on screen now (2D board), and how wide a space is there.
  @visibleForTesting
  (Offset, double)? debugSpaceOnScreen(int id) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final c = box.localToGlobal(geo.of(id));
    return (c, (box.localToGlobal(geo.of(id) + Offset(geo.radius, 0)) - c).distance);
  }

  /// Tests: the prompt waiting on this player, and the spaces it highlights.
  @visibleForTesting
  Prompt? get debugPrompt => _prompt;
  @visibleForTesting
  List<int> get debugMarkedSpaces => _marks.spaces.toList();

  /// Tests: where fighter [f] is drawn on screen now (2D board).
  @visibleForTesting
  Offset? debugFighterOnScreen(Fighter f) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !f.onBoard) return null;
    return box.localToGlobal(geo.of(f.space!) + slotOffset(game, f, geo.radius));
  }

  /// Tests: the middle of the path between two spaces, on screen now (2D board).
  @visibleForTesting
  Offset? debugEdgeOnScreen((int, int) e) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal((geo.of(e.$1) + geo.of(e.$2)) / 2);
  }

  /// Tests: whether a tap at [global] reaches the board (nothing of the HUD on top of it).
  @visibleForTesting
  bool debugTapReachesBoard(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return false;
    final r = HitTestResult();
    WidgetsBinding.instance.hitTestInView(r, global, View.of(context).viewId);
    return r.path.any((e) => e.target == box);
  }

  /// Tests: the picks of the last answered prompt, and a way to answer one directly.
  @visibleForTesting
  List<int>? debugLastPicks;
  @visibleForTesting
  void debugAnswer(List<int> picks) => _submit(picks);
  Size _viewport = Size.zero;
  Animation<Matrix4>? _camTween;

  /// The 3D map, when it's on (Settings > Battlefield) and this map and platform have one.
  Board3DController? _b3;
  StreamSubscription<Offset>? _b3Taps;
  bool _b3Failed = false;
  bool get _in3d => _b3 != null;

  /// The static board, rasterised once: drawing one texture per frame instead of every space,
  /// gradient and path keeps camera moves and animations cheap on phones and the web.
  ui.Image? _boardImage;

  double get _speed {
    final base = _s.settings.speed;
    // Once you're out, the rest of the game plays out quickly.
    return game.players.isNotEmpty && me.eliminated ? base * 0.35 : base;
  }

  // ======================================================================== lifecycle

  @override
  void initState() {
    super.initState();
    _moveA.addListener(() {
      final m = _move.value;
      if (m != null) m.t = _moveA.value;
    });
    _camA.addListener(() {
      if (_camTween != null) _cam.value = _camTween!.value;
    });
    _cam.addListener(_trackZoom);
  }

  void _trackZoom() {
    final s = _planeScale(_cam.value) * _dpr;
    if (s <= 0 || !s.isFinite) return;
    final step = math.pow(2, (math.log(s) / math.ln2 * 4).round() / 4).toDouble();
    if (step != _pxPerUnit.value) _pxPerUnit.value = step;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final cfg = widget.config;
    geo = BoardGeometry(cfg.map);
    final level = cfg.ai;
    game = Game(
      data: _s.data,
      map: cfg.map,
      heroIds: cfg.heroIds,
      teams: cfg.teams,
      seed: widget.seed,
      random: widget.net == null ? null : PortableRandom(widget.net!.seed),
      presenter: _present,
      agents: [for (var i = 0; i < cfg.heroIds.length; i++) _agentFor(i, level)],
    );
    final net = widget.net;
    if (net == null) {
      me
        ..label = _s.settings.username
        ..isAI = false;
      for (final p in game.players.skip(1)) {
        p
          ..label = 'AI ${level.label}'
          ..isAI = true;
      }
    } else {
      _applyNames();
      net.names.addListener(_applyNames);
      net.lost.addListener(_onLost);
    }
    _s.audio.music(Music.battle);
    _ensure3d();
    // The 2D board image is only needed without the 3D map (made later if the 3D map fails).
    if (_b3 == null) unawaited(_bakeBoard());
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Agent _agentFor(int seat, AiLevel level) {
    final human = HumanAgent(_onPrompt);
    final ai = PacedAgent(
      AiAgent(level: level),
      think: (p) => p.ask == Ask.action ? (650 * _speed).round() : (p.ask == Ask.card || p.ask == Ask.space ? (260 * _speed).round() : 0),
      onThinking: (p) {
        if (!_disposed && _thinking != p.player) setState(() => _thinking = p.player);
      },
    );
    final net = widget.net;
    if (net == null) return seat == 0 ? human : ai;
    return net.agentFor(seat, human: human, ai: ai);
  }

  /// Multiplayer: names per seat (an AI takes over for anyone who leaves).
  void _applyNames() {
    final net = widget.net!;
    final names = net.names.value;
    for (final p in game.players) {
      p
        ..label = p == me ? _s.settings.username : names[p.seat]
        ..isAI = net.aiSeats.contains(p.seat) || names[p.seat].endsWith('(AI)');
    }
    if (!_disposed && mounted) setState(() {});
  }

  /// Multiplayer: the connection is gone.
  Future<void> _onLost() async {
    final why = widget.net?.lost.value;
    if (why == null || _disposed || !mounted || _result != null) return;
    await showConfirm(context, title: 'Connection lost', message: why, confirm: 'Back to menu', cancel: 'Stay');
    if (mounted) _toMenu();
  }

  Future<void> _run() async {
    try {
      await _waitForBoard();
      if (_disposed) return;
      await game.run();
    } on _Abandoned {
      return;
    } catch (e, st) {
      debugPrint('Match error: $e\n$st');
      if (!_disposed) setState(() => _error = '$e');
    }
  }

  /// Holds the match until the 3D map is on screen, so the opening moves aren't missed.
  Future<void> _waitForBoard() async {
    final c = _b3;
    if (c == null || c.status.value != Board3DStatus.loading) return;
    final done = Completer<void>();
    void listen() {
      if (c.status.value != Board3DStatus.loading && !done.isCompleted) done.complete();
    }

    c.status.addListener(listen);
    await done.future.timeout(const Duration(seconds: 40), onTimeout: () => c.fail('it took too long to load'));
    try {
      c.status.removeListener(listen);
    } catch (_) {}
  }

  /// Creates, swaps or drops the 3D board to match the settings (also called from build, so a
  /// change made in the pause menu applies at once).
  void _ensure3d() {
    final settings = _s.settings;
    final want = settings.board3d && board3dSupported && hasModel(widget.config.map) && !_b3Failed;
    final graphics = settings.graphics3d;
    if (want && _b3 != null) {
      // Every graphics setting applies to the running view.
      _b3!.setGraphics(graphics);
      return;
    }
    if (!want && _b3 == null) return;
    _drop3d();
    if (!want) {
      if (_boardImage == null) unawaited(_bakeBoard());
      return;
    }
    final start = widget.config.map.spaces.where((s) => s.start == (widget.net?.localSeat ?? 0) + 1).firstOrNull;
    // The boards' print reads upright from the far (-y) side; seat the camera there unless your
    // start is clearly on the near half.
    final sy = start?.y ?? 0;
    final c = _b3 = Board3DController(map: widget.config.map, graphics: graphics, homeSide: sy > 1 ? 1 : -1);
    _b3Taps = c.taps.listen((p) => _onBoardTap(geo.world(p.dx, p.dy)));
    c.status.addListener(() {
      Future.microtask(() {
        if (_disposed || !mounted || _b3 != c) return;
        if (c.status.value == Board3DStatus.failed) {
          _b3Failed = true;
          _drop3d();
          if (_boardImage == null) unawaited(_bakeBoard());
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text('The 3D map could not be shown (${c.error}). Playing on the 2D board.')));
        }
        setState(() {});
      });
    });
  }

  void _drop3d() {
    _b3Taps?.cancel();
    _b3Taps = null;
    final c = _b3;
    _b3 = null;
    // After the frame, once the web view holding it is gone.
    if (c != null) WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  }

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Sends the board as it is now; the controller skips repeats.
  void _sync3d() {
    final c = _b3;
    if (c == null) return;
    final pend = _marks.pending;
    c.send({
      't': 'state',
      'fighters': [
        for (final f in game.fighters)
          if (f.onBoard)
            {
              'id': f.uid,
              'space': f.space,
              'tail': f.tail,
              'color': _hex(colorOf(f.owner)),
              'hero': f.isHero,
              'hp': f.hp,
              'name': f.name,
              // melee or ranged, for the attack chip on the fighter's tag
              if (f.isRanged) 'ranged': true,
              // which figure to draw: the hero's id, the fighter's id (a sidekick's token) and, for
              // heroes with several hero fighters (the three Raptors), which of them this is
              'mini': f.owner.hero.id,
              'fid': f.def.id,
              if (f.isHero) 'v': f.owner.fighters.where((x) => x.isHero).toList().indexOf(f),
              // the hero's pieces (Alice's card, Hellfire...) on the main hero's badge
              if (f == f.owner.heroFighter) 'items': [for (final i in heroItems(f.owner)) i.toJson()],
              if (f.isSmall) 'small': true,
              if (game.offsetInSpace(f) case (final x, final y) when x != 0 || y != 0) 'off': [x, y],
            },
      ],
      'marks': {
        'select': [for (final f in _marks.select) f.uid],
        'targets': [for (final f in _marks.targets) f.uid],
        'spaces': _marks.spaces.toList(),
        'edges': [
          for (final e in _marks.edges) [e.$1, e.$2],
        ],
        'subject': _marks.subject?.uid,
        'pendingFighter': pend is Fighter ? pend.uid : null,
        'pendingSpace': pend is int ? pend : null,
        'subjectSpace': _marks.subjectSpace,
        'pendingEdge': pend is (int, int) ? [pend.$1, pend.$2] : null,
        'preview': _marks.previewPath,
        'harmful': _marks.harmful,
      },
      'tokens': [
        for (final t in game.board.tokens)
          if (t.space != null)
            {'kind': t.kind, 'space': t.space}
          else if (t.path != null)
            {'kind': t.kind, 'a': t.path!.$1, 'b': t.path!.$2},
      ],
      'focus': _combat == null ? const <int>[] : [_combat!.attacker.fighter.uid, _combat!.defender.fighter.uid],
    });
  }

  Future<void> _bakeBoard() async {
    final art = widget.config.map.art;
    if (art != null) return _loadArt(art);
    final quality = _s.settings.quality;
    final maxDimension = math.max(geo.size.width, geo.size.height);
    final targetPixels = switch (quality) {
      Quality.low => 2048.0,
      Quality.medium => 2800.0,
      Quality.high => 3840.0,
      Quality.ultra => 4600.0,
    };
    final res = (targetPixels / maxDimension).clamp(1.0, quality.bakeScale);
    final size = geo.size * res;
    final recorder = ui.PictureRecorder();
    BoardPainter(geo, showStarts: false, detailed: true).paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(size.width.ceil(), size.height.ceil());
      if (_disposed) {
        image.dispose();
      } else {
        setState(() => _boardImage = image);
      }
    } catch (_) {
      // Keep painting the board live if the image can't be made.
    } finally {
      picture.dispose();
    }
  }

  /// The printed-style map art is the board: decoded with optimal fidelity based on quality preset,
  /// preserving 100% sharp native resolution on High and Ultra for crisp panning and zooming.
  Future<void> _loadArt(MapArt art) async {
    final quality = _s.settings.quality;
    try {
      final data = await rootBundle.load(art.asset);
      final maxWidth = quality.maxTextureWidth;
      final codec = await (maxWidth != null && maxWidth < art.w
          ? ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: maxWidth)
          : ui.instantiateImageCodec(data.buffer.asUint8List()));
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (_disposed) {
        frame.image.dispose();
      } else {
        setState(() => _boardImage = frame.image);
      }
    } catch (e) {
      debugPrint('Map art failed to load: $e');
    }
  }

  @override
  void dispose() {
    _boardImage?.dispose();
    _disposed = true;
    _drop3d();
    widget.net?.names.removeListener(_applyNames);
    widget.net?.lost.removeListener(_onLost);
    widget.net?.leave();
    if (_answer != null && !_answer!.isCompleted) _answer!.completeError(const _Abandoned());
    _pulse.dispose();
    for (final c in [_banner, _moveA, _fxA, _camA, _shakeA]) {
      c.dispose();
    }
    _move.dispose();
    _boardTick.dispose();
    _cam.removeListener(_trackZoom);
    _cam.dispose();
    _pxPerUnit.dispose();
    super.dispose();
  }

  // ======================================================================== presenting events

  /// Combat steps wait longer, by the combat pace setting, so the duel can be followed.
  Future<void> _waitCombat(int ms) => _wait((ms * _s.settings.combatPace.factor).round());

  Future<void> _wait(int ms) async {
    final d = (ms * _speed).round();
    if (d > 0) await Future<void>.delayed(Duration(milliseconds: d));
    if (_disposed) throw const _Abandoned();
  }

  void _refresh() {
    if (_disposed) return;
    _boardTick.value++;
    setState(() {});
  }

  Color colorOf(Player p) {
    final cfg = widget.config;
    if (cfg.teams != null) {
      final sameTeam = [
        for (final o in game.players)
          if (o.team == p.team) o,
      ];
      final shades = p.team == me.team ? Palette.teamA : Palette.teamB;
      return shades[sameTeam.indexOf(p) % shades.length];
    }
    if (game.players.length == 2) return p == me ? Palette.seats[0] : Palette.seats[1];
    return Palette.seats[p.seat % Palette.seats.length];
  }

  Future<void> _present(GameEvent e) async {
    if (_disposed) throw const _Abandoned();
    if (logIsPublic(e, me)) {
      _log.add(e is TurnStarted ? LogLine('Turn ${e.number} · ${e.player.name}', turn: true, color: colorOf(e.player)) : LogLine(e.log));
      if (_log.length > 400) _log.removeRange(0, 100);
    }
    final quality = _s.settings.quality;
    switch (e) {
      case TurnStarted(:final player):
        _thinking = null;
        final mine = player == me;
        _bannerTitle = mine ? 'Your turn' : "${player.name}'s turn";
        _bannerSub = mine ? 'Two actions: maneuver, scheme or attack' : player.label;
        _bannerColor = hexColor(player.hero.color);
        _refresh();
        _s.audio.sfx(Sfx.whoosh, volume: 0.7);
        _banner.duration = Duration(milliseconds: math.max(300, (1500 * _speed).round()));
        unawaited(_banner.forward(from: 0));
        await _wait(mine ? 1150 : 850);
      case FighterPlacedAtStart():
        _refresh();
        await _wait(140);
      case FighterMoved(:final fighter, :final path, :final placed):
        if (placed || path.length < 2) {
          _refresh();
          _s.audio.sfx(Sfx.step);
          await _wait(300);
        } else {
          final steps = path.length - 1;
          final ms = (190 * steps * _speed).round();
          if (ms <= 0) {
            _refresh();
            break;
          }
          _b3?.send({'t': 'move', 'id': fighter.uid, 'path': path, 'ms': ms});
          _move.value = MoveAnim(fighter, path);
          _moveA.duration = Duration(milliseconds: ms);
          for (var i = 0; i < steps; i++) {
            Future<void>.delayed(Duration(milliseconds: (ms * i / steps).round()), () {
              if (!_disposed) _s.audio.sfx(Sfx.step, volume: 0.7);
            });
          }
          await _moveA.forward(from: 0);
          _move.value = null;
          _refresh();
          if (_disposed) throw const _Abandoned();
        }
      case Swapped():
        _s.audio.sfx(Sfx.whoosh, volume: 0.6);
        _refresh();
        await _wait(350);
      case Damaged(:final fighter, :final amount):
        _s.audio.sfx(Sfx.hit);
        await _burst(fighter, '−$amount', Palette.target, sparks: true, shake: quality.shake);
      case Healed(:final fighter, :final amount):
        _s.audio.sfx(Sfx.heal);
        await _burst(fighter, '+$amount', Palette.good);
      case Defeated(:final fighter):
        _log.add(LogLine('${fighter.name} is defeated', turn: true, color: Palette.danger));
        final mine = fighter.owner == me;
        final enemy = fighter.isEnemyOf(me);
        _bannerTitle = fighter.isHero && mine ? 'Defeat' : '${fighter.name} defeated';
        _bannerSub = fighter.isHero
            ? (mine ? 'Your hero has fallen' : (enemy ? 'An enemy hero falls' : 'Your ally has fallen'))
            : (mine ? 'You lost a sidekick' : (enemy ? 'Enemy sidekick down' : 'Ally sidekick down'));
        _bannerColor = enemy ? Palette.good : Palette.danger;
        _s.audio.sfx(Sfx.hit);
        _refresh();
        _banner.duration = Duration(milliseconds: math.max(300, (1500 * _speed).round()));
        unawaited(_banner.forward(from: 0));
        await _wait(fighter.isHero ? 1300 : 800);
      case Returned():
        _refresh();
        await _wait(350);
      case CombatStarted(:final combat):
        _combat = combat;
        _revealed = false;
        _resolved = false;
        _resolving = null;
        _effectText = null;
        _s.audio.sfx(Sfx.whoosh);
        _refresh();
        if (quality.cameraEffects) _pushIn(combat);
        await _waitCombat(700);
      case PhaseChanged(:final phase):
        _refresh();
        if (phase.index >= Phase.immediately.index && phase.index <= Phase.after.index) await _waitCombat(300);
      case CardsRevealed():
        _revealed = true;
        _s.audio.sfx(Sfx.reveal);
        _refresh();
        await _waitCombat(1300);
      case EffectResolving(:final side, :final timing, :final text):
        _resolving = side;
        _effectText = '${side.card?.title.toUpperCase() ?? ''} · ${timing.toUpperCase()}${timing == 'after' ? ' COMBAT' : ''}: $text';
        _refresh();
        await _waitCombat(1500);
        _resolving = null;
        _effectText = null;
      case ValuesChanged() || Canceled() || CardSwapped():
        _refresh();
        await _waitCombat(450);
      case CombatResolved():
        _resolved = true;
        _refresh();
        await _waitCombat(1500);
      case CombatEnded():
        await _waitCombat(400);
        _combat = null;
        _resolved = false;
        _refresh();
        if (quality.cameraEffects && !_pulledForPick) _pullBack();
        _pulledForPick = false;
        await _wait(300);
      case SchemePlayed(:final card, :final fighter):
        _spot = (card, '${fighter.name} plays a scheme');
        _s.audio.sfx(Sfx.card);
        _refresh();
        await _wait(card.owner == me ? 900 : 1900);
        _spot = null;
        _refresh();
      case Boosted():
        // The boost card was already shown as it went to the discard pile (CardMoved).
        _refresh();
      case CardMoved(:final card, :final from, :final to, :final reason, :final reveal)
          when reveal && to == Zone.discard && (from == Zone.hand || reason.contains('boost')):
        // Every discard is public: boosts (blind ones too), random discards, hand limit...
        final who = card.owner == me ? 'You' : card.owner.name;
        final what = switch (reason) {
          final r when r.contains('blind boost') => '$who blind boost${card.owner == me ? '' : 's'} with',
          final r when r.contains('boost') => '$who boost${card.owner == me ? '' : 's'} with',
          final r when r.contains('random') => '$who discard${card.owner == me ? '' : 's'} at random',
          final r when r.contains('hand limit') => '$who discard${card.owner == me ? '' : 's'} (hand limit)',
          _ => '$who discard${card.owner == me ? '' : 's'}',
        };
        _spot = (card, what);
        _s.audio.sfx(Sfx.card, volume: 0.5);
        _refresh();
        await _wait(card.owner == me ? 800 : 1300);
        _spot = null;
        _refresh();
      case Revealed(:final player, :final cards, :final why, :final viewer) when cards.isNotEmpty && (viewer == null || viewer == me):
        final private = viewer == me && player != me;
        await _showReveal(
          private ? '${player.name}\'s hand' : '${player == me ? 'You reveal' : '${player.name} reveals'}$why',
          cards,
          private: private,
        );
      case CardsDrawn(:final player):
        if (player == me) _s.audio.sfx(Sfx.card, volume: 0.6);
        _refresh();
        await _wait(player == me ? 220 : 80);
      case ActionsChanged() || ActionTaken() || CardMoved() || StatusChanged() || Revealed() || LogEvent() || Exhausted():
        _refresh();
        if (e is StatusChanged) await _wait(300);
      case GameOver():
        _result = e;
        _clearPrompt();
        final won = game.winningTeam == me.team;
        final net = widget.net;
        if (net != null && net.isHost) {
          // Online: the lobby is wiped; only who won and who played are kept.
          final winners = [
            for (final p in game.players)
              if (p.team == game.winningTeam) p.label,
          ];
          unawaited(
            net.reportResult(winner: winners.isEmpty ? null : winners.join(' & '), players: [for (final p in game.players) p.label]),
          );
        }
        _s.audio.stopMusic();
        _s.audio.sfx(won ? Sfx.victory : Sfx.hit);
        _refresh();
      default:
        _refresh();
    }
  }

  /// Shows [cards] until the player taps OK (a hand being looked at) or a few seconds pass
  /// (public reveals), so effects that look at or reveal cards are visible.
  Future<void> _showReveal(String title, List<Card> cards, {required bool private}) async {
    if (_speed <= 0) return; // tests run at instant speed
    final done = _revealDone = Completer<void>();
    _reveal = (title: title, cards: List.of(cards), private: private);
    _s.audio.sfx(Sfx.reveal, volume: 0.6);
    _refresh();
    final limit = Duration(milliseconds: math.max(1500, ((private ? 9000 : 2600) * _speed).round()));
    await Future.any([done.future, Future<void>.delayed(limit)]);
    _reveal = null;
    _revealDone = null;
    if (_disposed) throw const _Abandoned();
    _refresh();
  }

  Future<void> _burst(Fighter f, String text, Color color, {bool sparks = false, bool shake = false}) async {
    if (f.space == null) {
      _refresh();
      return;
    }
    _fx
      ..clear()
      ..add(Fx(geo.of(f.space!), text, color, sparks: sparks));
    _refresh();
    final ms = (800 * _speed).round();
    _b3?.send({'t': 'fx', 'id': f.uid, 'text': text, 'color': _hex(color), 'sparks': sparks && _s.settings.quality.particles, 'ms': ms});
    if (shake) _in3d ? _b3!.send({'t': 'shake'}) : unawaited(_shakeA.forward(from: 0));
    if (ms > 0) {
      _fxA.duration = Duration(milliseconds: ms);
      await _fxA.forward(from: 0);
    }
    _fx.clear();
    if (_disposed) throw const _Abandoned();
    _refresh();
  }

  // ======================================================================== camera

  Matrix4 _fitMatrix(Size view) {
    // Leave room for the prompt bar on top and the hand along the bottom.
    const top = 46.0;
    // Phones: let the board run a little under the hand; it can be zoomed and panned anyway.
    final bottom = view.height * (view.height < 520 ? 0.16 : 0.26);
    final avail = Size(view.width - 24, view.height - top - bottom);
    final s = math.min(avail.width / geo.size.width, avail.height / geo.size.height);
    final dx = (view.width - geo.size.width * s) / 2;
    final dy = top + (avail.height - geo.size.height * s) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, s, 1);
  }

  void _animateCam(Matrix4 to, {Duration? d, Curve curve = Curves.easeInOutCubic, Offset? anchor}) {
    _camGoal = to;
    final from = _cam.value.clone();
    _camTween = _CamTween(from, to, anchor ?? _viewport.center(Offset.zero)).animate(CurvedAnimation(parent: _camA, curve: curve));
    _camA.duration = d ?? Duration(milliseconds: math.max(1, (650 * _s.settings.speed).round()));
    _camA.forward(from: 0);
  }

  /// Where a running camera move ends (wheel notches add up from there).
  Matrix4? _camGoal;

  /// Mouse wheel / trackpad scroll over the 2D board: a smooth zoom that keeps the point under the
  /// pointer still. [scene] is that point in board coordinates.
  void _wheel(PointerScrollEvent e, Offset scene) {
    if (e.scrollDelta.dy == 0) return;
    final factor = math.exp(-e.scrollDelta.dy.clamp(-300.0, 300.0) / 800);
    final base = _camA.isAnimating && _camGoal != null ? _camGoal! : _cam.value;
    final next = (_planeScale(base) * factor).clamp(_minScale, _maxScale);
    final screen = MatrixUtils.transformPoint(_cam.value, scene);
    _animateCam(
      Matrix4.identity()
        ..translateByDouble(screen.dx - scene.dx * next, screen.dy - scene.dy * next, 0, 1)
        ..scaleByDouble(next, next, next, 1),
      d: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      anchor: screen,
    );
  }

  void _fit() {
    if (_in3d) return _b3!.send({'t': 'cam', 'op': 'fit'});
    if (_viewport == Size.zero) return;
    _camHome = _fitMatrix(_viewport);
    _animateCam(_camHome!, d: const Duration(milliseconds: 380));
  }

  void _zoom(double factor) {
    if (_in3d) return _b3!.send({'t': 'cam', 'op': 'zoom', 'k': factor});
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    final m = _cam.value.clone();
    final scene = _cam.toScene(c);
    final cur = _planeScale(m);
    final next = (cur * factor).clamp(_minScale, _maxScale);
    final k = next / cur;
    final to = m
      ..translateByDouble(scene.dx, scene.dy, 0, 1)
      ..scaleByDouble(k, k, k, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
    _animateCam(to, d: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  double get _minScale => (_camHome == null ? 0.3 : _planeScale(_camHome!)) * 0.7;
  double get _maxScale => (_camHome == null ? 0.3 : _planeScale(_camHome!)) * 3.5;

  /// The dramatic push-in: frame the two fighters between the combat cards.
  void _pushIn(Combat c) {
    final a = c.attacker.fighter.space, d = c.defender.fighter.space;
    if (a == null || d == null) return;
    if (_in3d) return _b3!.send({'t': 'cam', 'op': 'push', 'a': a, 'b': d, 'ms': _camMs(800)});
    if (_viewport == Size.zero) return;
    final pa = geo.of(a), pd = geo.of(d);
    final mid = Offset.lerp(pa, pd, 0.5)!;
    final span = (pa - pd).distance + geo.unit * 2.2;
    final home = _camHome == null ? 0.4 : _planeScale(_camHome!);
    final want = (_viewport.width * 0.36) / span;
    final s = want.clamp(home * 1.15, home * 2.4);
    // Below the combat cards, which sit across the top of the screen.
    final target = Offset(_viewport.width / 2, _viewport.height * 0.8);
    _animateCam(
      Matrix4.identity()
        ..translateByDouble(target.dx - mid.dx * s, target.dy - mid.dy * s, 0, 1)
        ..scaleByDouble(s, s, s, 1),
      d: Duration(milliseconds: _camMs(800)),
    );
  }

  /// A camera move's length at the animation speed setting. Duel moves are a touch longer than
  /// the rest, so the swing round the fighters reads as one unhurried motion.
  int _camMs(int ms) => math.max(1, (ms * _s.settings.speed).round());

  void _pullBack() {
    if (_in3d) return _b3!.send({'t': 'cam', 'op': 'pull', 'ms': _camMs(720)});
    if (_camHome != null) _animateCam(_camHome!, d: Duration(milliseconds: _camMs(720)));
  }

  // ======================================================================== prompts

  /// The camera pulled back from the duel so a board choice can be made (re-pushed after).
  bool _pulledForPick = false;

  /// A card effect asks you to pick on the board in the middle of a combat (move a fighter,
  /// place one, choose a space or path): the combat cards step aside until you're done.
  bool get _pickingInCombat => _combat != null && (_isBoardSpacePrompt || _isFighterPrompt || _isPathPrompt);

  /// The combat cards cover the screen (not while you pick on the board).
  bool get _combatCovers => _combat != null && !_pickingInCombat;

  void _onPrompt(Prompt p, Completer<List<int>> c) {
    if (_disposed) {
      c.completeError(const _Abandoned());
      return;
    }
    _prompt = p;
    _answer = c;
    _attackMode = false;
    _attackTarget = null;
    _schemeHint = false;
    _thinking = null;
    _computeMarks();
    if (_marks.any && _s.settings.quality.pulse) {
      _pulse.start(_s.settings.quality.pulseStep);
    }
    if (_pickingInCombat && !_pulledForPick && _s.settings.quality.cameraEffects) {
      // Show the board around the fighters, not the close-up of the duel.
      _pulledForPick = true;
      _pullBack();
    }
    _refresh();
    if (widget.autoplay) {
      Future<void>.delayed(Duration(milliseconds: (900 * _speed).round()), () async {
        if (_disposed || _prompt != p) return;
        _submit(await AiAgent(level: AiLevel.hard).decide(game, p));
      });
    }
  }

  void _clearPrompt() {
    _prompt = null;
    _answer = null;
    _attackMode = false;
    _attackTarget = null;
    _schemeHint = false;
    _marks.clear();
    _pulse.stop();
  }

  void _submit(List<int> picks) {
    final c = _answer;
    if (c == null || c.isCompleted) return;
    debugLastPicks = picks;
    _clearPrompt();
    _refresh();
    c.complete(picks);
    if (_pulledForPick) {
      // Back to the duel once the moving is over (not between two picks of one effect).
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (_disposed || !_pulledForPick || _pickingInCombat) return;
        _pulledForPick = false;
        if (_combat != null) _pushIn(_combat!);
      });
    }
  }

  List<Object?> get _values => [for (final c in _prompt?.choices ?? const <Choice<Object?>>[]) c.value];

  int? _indexOf(Object? v) {
    final i = _values.indexWhere((x) => identical(x, v) || x == v);
    return i < 0 ? null : i;
  }

  /// The fighter tapped in [space]. Small fighters can share a space: prefer one the current
  /// prompt can use, then the one drawn nearest the tap.
  Fighter? _fighterAtTap(int space, Offset local) {
    final here = game.fightersAt(space);
    if (here.length <= 1) return here.firstOrNull;
    final useful = here
        .where(
          (f) => _isFighterPrompt
              ? _indexOf(f) != null
              : _actions.any((a) => a.kind == ActionKind.attack && (a.target == f || a.fighter == f)),
        )
        .toList();
    final pool = useful.isNotEmpty ? useful : here;
    double d(Fighter f) => (geo.of(space) + slotOffset(game, f, geo.radius) - local).distanceSquared;
    pool.sort((a, b) => d(a).compareTo(d(b)));
    return pool.first;
  }

  void _heroSheet(Player p) => showHeroSheet(context, players: [me, ...game.players.where((o) => o != me)], initial: p, me: me);

  /// A space choice may be a plain space id or a token sitting on a space (fog).
  int? _spaceOf(Object? v) => v is int ? v : (v is Token ? v.space : null);

  bool get _isBoardSpacePrompt => _prompt?.ask == Ask.space && _values.every((v) => _spaceOf(v) != null);
  bool get _isFighterPrompt => _prompt?.ask == Ask.fighter && _values.every((v) => v is Fighter && v.onBoard);
  bool get _isHandCardPrompt => _prompt?.ask == Ask.card && _values.every((v) => v is Card && me.hand.contains(v));
  bool get _isPathPrompt => _prompt?.ask == Ask.path && _values.every((v) => v is (int, int));

  List<ActionChoice> get _actions => [
    for (final v in _values)
      if (v is ActionChoice) v,
  ];

  void _computeMarks() {
    _marks.clear();
    final p = _prompt;
    if (p == null) return;
    if (p.ask == Ask.action) {
      final attacks = _actions.where((a) => a.kind == ActionKind.attack).toList();
      if (_attackMode) {
        if (_attackTarget == null) {
          _marks.targets.addAll(attacks.map((a) => a.target!));
          _marks.select.addAll(attacks.map((a) => a.fighter!));
        } else {
          _marks.targets.add(_attackTarget!);
          _marks.select.addAll(attacks.where((a) => a.target == _attackTarget).map((a) => a.fighter!));
        }
      }
    } else if (_isFighterPrompt) {
      final fs = _values.cast<Fighter>();
      if (p.intent == Intent.harm || p.intent == Intent.attackTarget || p.intent == Intent.moveEnemy) {
        _marks.targets.addAll(fs);
      } else {
        _marks.select.addAll(fs);
      }
    } else if (_isBoardSpacePrompt) {
      _marks.spaces.addAll(_values.map(_spaceOf).whereType<int>());
      final subj = p.subject;
      if (subj is Fighter && subj.onBoard) {
        _marks.subject = subj;
        _marks.spaces.remove(subj.space);
      } else if (subj is Token && subj.space != null) {
        // Moving a token (Invisible Man's fog): ring the one that's moving. Its own space stays
        // a choice when it may stay put ("up to N spaces").
        _marks.subjectSpace = subj.space;
      }
      _marks.harmful = p.intent == Intent.moveEnemy || p.intent == Intent.harm;
    } else if (_isPathPrompt) {
      _marks.edges.addAll(_values.cast<(int, int)>());
    }
  }

  /// Hand cards that can be picked right now.
  Set<Card> get _playable {
    final p = _prompt;
    if (p == null) return const {};
    if (_isHandCardPrompt) return _values.cast<Card>().toSet();
    if (p.ask == Ask.action && !_attackMode) {
      final schemes = _actions.where((a) => a.kind == ActionKind.scheme).map((a) => a.card!.def.key).toSet();
      return me.hand.where((c) => schemes.contains(c.def.key)).toSet();
    }
    return const {};
  }

  // ------------------------------------------------------------------ board input

  void _onBoardTap(Offset local) {
    final p = _prompt;
    if (p == null) return;
    final space = geo.spaceAt(local);
    final fighter = space == null ? null : _fighterAtTap(space, local);

    if (p.ask == Ask.action) {
      final attacks = _actions.where((a) => a.kind == ActionKind.attack).toList();
      if (fighter == null) return;
      if (_attackTarget != null && attacks.any((a) => a.target == _attackTarget && a.fighter == fighter)) {
        _confirmAttack(fighter, _attackTarget!);
        return;
      }
      final asTarget = attacks.where((a) => a.target == fighter).toList();
      if (asTarget.isEmpty) return;
      _attackMode = true;
      if (asTarget.length == 1) {
        _confirmAttack(asTarget.first.fighter!, fighter);
      } else {
        _attackTarget = fighter;
        _computeMarks();
        _refresh();
      }
      return;
    }

    if (_isFighterPrompt && fighter != null) {
      final i = _indexOf(fighter);
      if (i == null) return;
      // Only attacks ask "Are you sure?"; everything else happens on the first tap.
      _submit([i]);
      return;
    }

    if (_isBoardSpacePrompt) {
      // The nearest space that can be picked, within a couple of space-widths: a tap on a fog
      // cloud (drawn above its space), a fighter on the space, or a fat finger just off the
      // circle still picks it; a tap far from every choice does nothing.
      int? best;
      var bestD = geo.radius * 2.2;
      for (final v in _values) {
        final s = _spaceOf(v);
        if (s == null) continue;
        final d = (geo.of(s) - local).distance;
        if (d < bestD) {
          bestD = d;
          best = s;
        }
      }
      if (best == null) return;
      final i = _values.indexWhere((v) => _spaceOf(v) == best);
      _s.audio.sfx(Sfx.click, volume: 0.4);
      _submit([i]);
      return;
    }

    if (_isPathPrompt) {
      final e = geo.edgeAt(local, _values.cast<(int, int)>());
      if (e == null) return;
      _submit([_indexOf(e)!]);
    }
  }

  void _confirmPending() {
    final pend = _marks.pending;
    if (pend == null) return;
    if (pend is Fighter) {
      final i = _indexOf(pend);
      if (i != null) _submit([i]);
    } else if (pend is int) {
      final i = _values.indexWhere((v) => _spaceOf(v) == pend);
      if (i >= 0) _submit([i]);
    } else if (pend is (int, int)) {
      final i = _indexOf(pend);
      if (i != null) _submit([i]);
    }
  }

  Future<void> _confirmAttack(Fighter attacker, Fighter target) async {
    final i = _actions.indexWhere((a) => a.kind == ActionKind.attack && a.fighter == attacker && a.target == target);
    if (i < 0) return;
    final idx = _values.indexOf(_actions[i]);
    if (_s.settings.confirmActions) {
      _marks
        ..targets.clear()
        ..targets.add(target)
        ..select.clear()
        ..select.add(attacker);
      _refresh();
      final ok = await showConfirm(
        context,
        title: 'Attack ${target.name}?',
        message: '${attacker.name} attacks. You choose the attack card next.',
        confirm: 'Attack',
      );
      if (!mounted || _prompt == null) return;
      if (!ok) {
        _attackTarget = null;
        _computeMarks();
        _refresh();
        return;
      }
    }
    _submit([idx]);
  }

  // ------------------------------------------------------------------ actions & cards

  void _startManeuver() {
    final i = _values.indexWhere((v) => v is ActionChoice && v.kind == ActionKind.maneuver);
    if (i >= 0) _submit([i]);
  }

  void _toggleAttack() {
    _attackMode = !_attackMode;
    _attackTarget = null;
    _schemeHint = false;
    _computeMarks();
    if (_marks.any && _s.settings.quality.pulse) _pulse.start();
    _refresh();
  }

  void _schemes() {
    final schemes = _actions.where((a) => a.kind == ActionKind.scheme).toList();
    if (schemes.length == 1) {
      _tapCard(schemes.first.card!);
      return;
    }
    setState(() {
      _attackMode = false;
      _schemeHint = true;
      _computeMarks();
    });
  }

  Future<void> _tapCard(Card card) async {
    final p = _prompt;
    final actions = <Widget>[];
    String? caption;
    if (p != null && p.ask == Ask.action) {
      final scheme = _actions.where((a) => a.kind == ActionKind.scheme && a.card!.def.key == card.def.key).firstOrNull;
      if (scheme != null && _schemeHint) {
        // SCHEME was pressed first: the tap is the choice.
        _s.audio.sfx(Sfx.card, volume: 0.6);
        _submit([_values.indexOf(scheme)]);
        return;
      } else if (scheme != null) {
        actions.add(_zoomAction('Play this scheme', Icons.auto_awesome_rounded, () => _submit([_values.indexOf(scheme)])));
      } else if (card.def.canAttack) {
        caption = 'To attack, tap ATTACK and choose a target. You pick the card after.';
      }
    } else if (p != null && _isHandCardPrompt && _values.contains(card)) {
      final i = _values.indexOf(card);
      // Only the attack card asks first; defending, boosting and other picks take one tap.
      // (Long-press or right-click a card to read it.)
      if (p.intent != Intent.attackCard || !_s.settings.confirmActions) {
        _s.audio.sfx(Sfx.card, volume: 0.6);
        _submit([i]);
        return;
      }
      actions.add(_zoomAction('Attack with this card', Icons.flash_on_rounded, () => _submit([i])));
    }
    await showCardZoom<void>(context, card.def.image, caption: caption, actions: actions);
  }

  void _readCard(Card card) => showCardZoom<void>(context, card.def.image);

  Widget _zoomAction(String label, IconData icon, VoidCallback onTap) => Builder(
    builder: (ctx) => PlateButton(
      label: label,
      icon: icon,
      style: PlateStyle.confirm,
      height: 50,
      fontSize: 16,
      onPressed: () {
        Navigator.of(ctx).pop();
        onTap();
      },
    ),
  );

  Future<void> _skip() async {
    final p = _prompt;
    if (p == null || !p.optional) return;
    _submit(const []);
  }

  // ======================================================================== menus

  Future<void> _pause() async {
    final r = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Resume',
      barrierColor: const Color(0xB3000000),
      pageBuilder: (ctx, _, _) => Center(
        child: Material(
          color: Colors.transparent,
          child: Panel(
            padding: const EdgeInsets.all(22),
            cut: 14,
            child: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('PAUSED', textAlign: TextAlign.center, style: titleStyle(30, spacing: 4)),
                  const Center(child: DecoRule(width: 160, opacity: 0.4)),
                  const SizedBox(height: 16),
                  PlateButton(
                    label: 'Resume',
                    icon: Icons.play_arrow_rounded,
                    height: 50,
                    onPressed: () => Navigator.of(ctx).pop('resume'),
                  ),
                  const SizedBox(height: 12),
                  PlateButton(
                    label: 'Settings',
                    icon: Icons.tune_rounded,
                    style: PlateStyle.secondary,
                    height: 50,
                    onPressed: () => Navigator.of(ctx).pop('settings'),
                  ),
                  const SizedBox(height: 12),
                  PlateButton(
                    label: 'Leave match',
                    icon: Icons.logout_rounded,
                    style: PlateStyle.danger,
                    height: 50,
                    onPressed: () => Navigator.of(ctx).pop('leave'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (r == 'settings') {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen(inMatch: true)));
      if (mounted) setState(() {});
    } else if (r == 'leave') {
      final ok = await showConfirm(
        context,
        title: 'Leave the match?',
        message: 'This match can\'t be resumed.',
        confirm: 'Leave',
        danger: true,
      );
      if (ok && mounted) _toMenu();
    }
  }

  void _toMenu() {
    widget.net?.leave();
    _s.audio.music(Music.menu);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _rematch() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => MatchScreen(config: widget.config.rematch()),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  // ======================================================================== build

  String get _promptText {
    final p = _prompt;
    if (_result != null) return 'Game over';
    if (p == null) {
      if (_thinking != null) return '${_thinking!.name} is thinking…';
      if (game.turnNumber == 0) return 'Setting up the battlefield…';
      return game.active == me ? 'Resolving…' : "${game.active.name}'s turn";
    }
    if (p.ask == Ask.action) {
      final left = game.actions + 1;
      if (_attackMode) {
        return _attackTarget == null ? 'Tap a red-marked fighter to attack' : 'Choose who attacks ${_attackTarget!.name}';
      }
      if (_schemeHint) return 'Tap a glowing scheme card in your hand';
      return 'Your turn · choose an action ($left left)';
    }
    if (_isFighterPrompt && _marks.pending != null) return '${p.text} · tap again or confirm';
    if (_isBoardSpacePrompt && _marks.pending != null) return 'Tap again or press ✓ to confirm';
    return switch (p.intent) {
      Intent.attackCard => 'Choose an attack card from your hand',
      Intent.defenseCard => 'Play a defense card, or skip',
      _ => p.text,
    };
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final p = _prompt;
    final settings = _s.settings;
    final isCompact = size.height < 550 || size.width < 900;
    // The HUD was laid out for a landscape phone (~412 px tall); bigger screens scale it up.
    final ui = (size.shortestSide / 470).clamp(1.0, 1.4);
    final cardW = (size.height * 0.27 * cardAspect).clamp(60.0, 200.0);
    final others = game.players.where((o) => o != me).toList();
    // HUD regions, worked out from the pieces' real sizes (each drawn `ui` times larger) so that
    // nothing covers anything else at any screen size: the menu row top-left with the camera
    // button under it; down the left, your allies (team games) above your plate; down the right,
    // your opponents above the action buttons; the prompt bar between the top corners; the hand
    // between your plate and the action buttons.
    final pad = MediaQuery.paddingOf(context);
    final bigPlate = size.width >= 900 && size.height >= 550;
    final menuButtons = canToggleFullscreen && !isFullscreen ? 4 : 3;
    final menuW = (menuButtons * 44 * 1.16 + (menuButtons - 1) * 6) * ui;
    final camTop = 8 + 44 * ui + 10;
    final camBottom = camTop + 38 * ui;
    final allies = [for (final o in others) if (o.team == me.team) o];
    final enemies = [for (final o in others) if (o.team != me.team) o];
    final compactEnemies = enemies.length > 1 || allies.isNotEmpty || size.height < 560;
    final enemiesW = enemies.isEmpty ? 0.0 : (compactEnemies ? _MiniPlate.width : PlayerPlate.widthFor(big: false)) * ui;
    final handLeft = pad.left + 10 + PlayerPlate.widthFor(big: bigPlate) * ui + 10;
    final handRight = pad.right + 10 + _actionClusterWidth(isCompact) * ui + 10;
    final combatCardH = (size.height * 0.46).clamp(150.0, 380.0);
    final playable = _playable;
    final boardPick = _marks.pending != null;
    final focus = _combat == null ? <Fighter>{} : {_combat!.attacker.fighter, _combat!.defender.fighter};
    _ensure3d();
    _sync3d();
    // During combat the hand drops out of the way of the fighters, unless a card is to be picked.
    final handDown = _combat != null && !_isHandCardPrompt;
    // Whole cards show above the bottom edge (and the phone's gesture bar).
    final handH = cardW / cardAspect + 10 + cardW * 0.06 + MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _result == null) _pause();
      },
      child: Scaffold(
        backgroundColor: Palette.bgDeep,
        body: TableBackground(
          ornament: false,
          child: Stack(
            children: [
              // The board with its camera: the 3D map, or the 2D board.
              if (_b3 != null)
                Positioned.fill(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Board3DView(key: ObjectKey(_b3), controller: _b3!),
                        ),
                      ),
                      Positioned.fill(child: _Board3DInput(controller: _b3!)),
                      Positioned.fill(
                        child: ValueListenableBuilder<Board3DStatus>(
                          valueListenable: _b3!.status,
                          builder: (_, st, _) => st == Board3DStatus.ready
                              ? const SizedBox.shrink()
                              : _Board3DCover(map: widget.config.map.name, progress: _b3!.progress),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final view = c.biggest;
                      final dpr = MediaQuery.devicePixelRatioOf(context);
                      if (dpr != _dpr) {
                        _dpr = dpr;
                        _trackZoom();
                      }
                      if (view != _viewport) {
                        _viewport = view;
                        final first = _camHome == null;
                        _camHome = _fitMatrix(view);
                        if (first) _cam.value = _camHome!.clone();
                      }
                      return AnimatedBuilder(
                        animation: _shakeA,
                        builder: (_, child) {
                          final t = _shakeA.value;
                          final dx = t == 0 || t == 1 ? 0.0 : math.sin(t * math.pi * 7) * 7 * (1 - t);
                          return Transform.translate(offset: Offset(dx, 0), child: child);
                        },
                        child: InteractiveViewer(
                            transformationController: _cam,
                            constrained: false,
                            minScale: _minScale,
                            maxScale: _maxScale,
                            clipBehavior: Clip.hardEdge,
                            boundaryMargin: EdgeInsets.all(math.max(view.width, view.height)),
                            scaleEnabled: true,
                            trackpadScrollCausesScale: false,
                            onInteractionStart: (_) => _camA.stop(),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (d) => _onBoardTap(d.localPosition),
                              // The wheel zooms smoothly toward the pointer (claimed here, before
                              // InteractiveViewer's own instant per-notch zoom).
                              child: Listener(
                                onPointerSignal: (e) {
                                  if (e is! PointerScrollEvent) return;
                                  final scene = e.localPosition;
                                  GestureBinding.instance.pointerSignalResolver.register(e, (ev) => _wheel(ev as PointerScrollEvent, scene));
                                },
                                child: SizedBox(
                                  key: _boardKey,
                                  width: geo.size.width,
                                  height: geo.size.height,
                                  child: Stack(
                                    children: [
                                      RepaintBoundary(
                                        child: _boardImage == null
                                            ? CustomPaint(size: geo.size, painter: BoardPainter(geo, showStarts: false, detailed: true))
                                            : ValueListenableBuilder<double>(
                                                valueListenable: _pxPerUnit,
                                                builder: (_, px, _) => RawImage(
                                                  image: _boardImage,
                                                  width: geo.size.width,
                                                  height: geo.size.height,
                                                  fit: BoxFit.fill,
                                                  filterQuality: settings.quality.filterFor(px * geo.size.width / _boardImage!.width),
                                                ),
                                              ),
                                      ),
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          size: geo.size,
                                          painter: BoardLayerPainter(
                                            game: game,
                                            geo: geo,
                                            marks: _marks,
                                            colorOf: colorOf,
                                            quality: settings.quality,
                                            pxPerUnit: _pxPerUnit,
                                            move: _move,
                                            pulse: _pulse,
                                            fxT: _fxA,
                                            fx: _fx,
                                            focus: focus,
                                            repaint: Listenable.merge([_boardTick, _moveA, _pulse, _fxA, _pxPerUnit, FigureArt.instance.loaded]),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ),
                      );
                    },
                  ),
                ),

              // Dim the edges during combat so the duel reads first.
              if (_combatCovers)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(radius: 0.9, colors: [Colors.transparent, Color(0x99000000)], stops: [0.35, 1]),
                      ),
                    ),
                  ),
                ),

              // Combat cards; they step aside while a card effect has you pick on the board.
              if (_combat != null)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_combatCovers,
                    child: AnimatedOpacity(
                      opacity: _combatCovers ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: CombatView(
                        game: game,
                        combat: _combat!,
                        me: me,
                        revealed: _revealed,
                        resolved: _resolved,
                        resolving: _resolving,
                        effectText: _effectText,
                        cardHeight: combatCardH,
                        onZoom: (c) => showCardZoom<void>(context, c.def.image),
                      ),
                    ),
                  ),
                ),

              // Prompt bar.
              Positioned(
                top: 0,
                left: pad.left + 10 + menuW + 8,
                right: pad.right + 10 + enemiesW + 8,
                child: SafeArea(
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, c) => Center(
                      child: _scaled(
                        ui,
                        Alignment.topCenter,
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: c.maxWidth / ui),
                          child: PromptBar(
                            text: _promptText,
                            mine: p != null,
                            source: p?.source?.def.image,
                            onSource: p?.source == null ? null : () => showCardZoom<void>(context, p!.source!.def.image),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Top-left: menu and log.
              Positioned(
                top: 8,
                left: 10,
                child: SafeArea(
                  child: _scaled(
                    ui,
                    Alignment.topLeft,
                    Row(
                      children: [
                        HexButton(icon: Icons.menu_rounded, tooltip: 'Menu', size: 44, onPressed: _pause),
                        const SizedBox(width: 6),
                        HexButton(
                          icon: Icons.receipt_long_rounded,
                          tooltip: 'Game log',
                          size: 44,
                          onPressed: () => setState(() => _showLog = !_showLog),
                        ),
                        const SizedBox(width: 6),
                        HexButton(icon: Icons.badge_rounded, tooltip: 'Identity cards', size: 44, onPressed: () => _heroSheet(me)),
                        if (canToggleFullscreen && !isFullscreen) ...[
                          const SizedBox(width: 6),
                          HexButton(
                            icon: Icons.fullscreen_rounded,
                            tooltip: 'Full screen',
                            size: 44,
                            onPressed: () async {
                              await toggleFullscreen();
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              if (_b3 != null && settings.showFps)
                Positioned(
                  top: 62,
                  left: 14,
                  child: SafeArea(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<int?>(
                        valueListenable: _b3!.fps,
                        builder: (_, v, _) => Text(
                          v == null ? '' : (v == 0 ? 'FPS · idle' : '$v FPS'),
                          style: titleStyle(13, color: v != null && v > 0 && v < 30 ? Palette.danger : Palette.good, spacing: 1),
                        ),
                      ),
                    ),
                  ),
                ),

              // Camera controls: one button under the menu that opens the rest beside it (a row, so
              // it never reaches down over your allies or your plate).
              Positioned(
                left: 10,
                top: camTop,
                child: SafeArea(
                  child: _hideInCombat(
                    Align(
                      alignment: Alignment.topLeft,
                      child: _scaled(
                        ui,
                        Alignment.topLeft,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HexButton(
                              icon: _camOpen ? Icons.chevron_left_rounded : Icons.videocam_rounded,
                              tooltip: _camOpen ? 'Hide camera controls' : 'Camera controls',
                              size: 38,
                              onPressed: () => setState(() => _camOpen = !_camOpen),
                            ),
                            if (_camOpen) ...[
                              const SizedBox(width: 6),
                              HexButton(icon: Icons.add_rounded, tooltip: 'Zoom in', size: 38, onPressed: () => _zoom(1.25)),
                              const SizedBox(width: 6),
                              HexButton(icon: Icons.remove_rounded, tooltip: 'Zoom out', size: 38, onPressed: () => _zoom(0.8)),
                              const SizedBox(width: 6),
                              HexButton(icon: Icons.fit_screen_rounded, tooltip: 'Fit board', size: 38, onPressed: _fit),
                              if (_in3d) ...[
                                const SizedBox(width: 6),
                                HexButton(
                                  icon: Icons.rotate_left_rounded,
                                  tooltip: 'Turn the board',
                                  size: 38,
                                  onPressed: () => _b3?.send({'t': 'cam', 'op': 'turn', 'a': math.pi / 4}),
                                ),
                                const SizedBox(width: 6),
                                HexButton(
                                  icon: Icons.threed_rotation_rounded,
                                  tooltip: 'Top view / table view',
                                  size: 38,
                                  onPressed: () => _b3?.send({'t': 'cam', 'op': 'tilt'}),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom: your hand.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: handLeft,
                right: handRight,
                bottom: handDown ? -handH * 0.62 : 0,
                height: handH,
                child: HandFan(
                  cards: me.hand,
                  playable: playable,
                  dimOthers: _isHandCardPrompt,
                  cardWidth: cardW,
                  onTap: _tapCard,
                  onRead: _readCard,
                ),
              ),

              // Down the left: your allies (team games) under the camera button, you at the bottom.
              // The allies shrink to fit the space your plate leaves them.
              Positioned(
                left: 10,
                top: camBottom + 10,
                bottom: 10,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: allies.isEmpty
                            ? const SizedBox.shrink()
                            : _hideInCombat(
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topLeft,
                                  child: _scaled(
                                    ui,
                                    Alignment.topLeft,
                                    _OpponentColumn(
                                      key: const ValueKey('hud-allies'),
                                      players: allies,
                                      active: game.turnNumber == 0 ? null : game.active,
                                      colorOf: colorOf,
                                      me: me,
                                      actions: game.actions,
                                      compact: true,
                                      left: true,
                                      onTap: _heroSheet,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 10),
                      _scaled(
                        ui,
                        Alignment.bottomLeft,
                        PlayerPlate(
                          key: const ValueKey('hud-me'),
                          player: me,
                          color: colorOf(me),
                          subtitle: settings.username,
                          big: bigPlate,
                          active: game.turnNumber > 0 && game.active == me,
                          actionsLeft: game.turnNumber > 0 && game.active == me
                              ? (p?.ask == Ask.action ? game.actions + 1 : game.actions)
                              : null,
                          onTap: () => _heroSheet(me),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Down the right: your opponents at the top, the actions (skip, confirm) at the bottom.
              // The opponents shrink to fit above the actions.
              Positioned(
                right: 10,
                top: 8,
                bottom: 12,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: enemies.isEmpty
                            ? const SizedBox.shrink()
                            : _hideInCombat(
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topRight,
                                  child: _scaled(
                                    ui,
                                    Alignment.topRight,
                                    _OpponentColumn(
                                      key: const ValueKey('hud-opponents'),
                                      players: enemies,
                                      active: game.turnNumber == 0 ? null : game.active,
                                      colorOf: colorOf,
                                      me: me,
                                      actions: game.actions,
                                      compact: compactEnemies,
                                      onTap: _heroSheet,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 10),
                      _scaled(
                        ui,
                        Alignment.bottomRight,
                        KeyedSubtree(key: const ValueKey('hud-actions'), child: _actionCluster(p, boardPick, compact: isCompact)),
                      ),
                    ],
                  ),
                ),
              ),

              // A scheme or boost card in the spotlight.
              if (_spot != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(_spot!.$1.uid),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutBack,
                        builder: (_, t, child) => Opacity(
                          opacity: t.clamp(0, 1),
                          child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(16, 3, 22, 4),
                              decoration: ShapeDecoration(
                                color: plateColor(hexColor(_spot!.$1.owner.hero.color)),
                                shape: const PlateBorder(side: BorderSide(color: Palette.bone)),
                              ),
                              child: Text(_spot!.$2.toUpperCase(), style: titleStyle(15, color: Colors.white, spacing: 1)),
                            ),
                            const SizedBox(height: 8),
                            CardImage(_spot!.$1.def.image, width: (size.height * 0.55 * cardAspect).clamp(110, 260)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Cards shown to you.
              if (_reveal != null)
                Positioned.fill(
                  child: RevealView(
                    title: _reveal!.title,
                    images: [for (final c in _reveal!.cards) c.def.image],
                    cardWidth: (size.height * 0.42 * cardAspect).clamp(80.0, 200.0),
                    onZoom: (i) => showCardZoom<void>(context, _reveal!.cards[i].def.image),
                    onDone: () {
                      if (!(_revealDone?.isCompleted ?? true)) _revealDone!.complete();
                    },
                  ),
                ),

              // Panels for choices that aren't on the board or in your hand.
              if (p != null) ?_choiceOverlay(p),

              // The game log.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: _showLog ? 10 : -360,
                top: 60,
                bottom: 10,
                width: math.min(340, size.width * 0.45),
                child: LogPanel(lines: _log, onClose: () => setState(() => _showLog = false)),
              ),

              TurnBanner(animation: _banner, title: _bannerTitle, sub: _bannerSub, color: _bannerColor),

              if (_result != null)
                Positioned.fill(
                  child: ResultView(
                    won: game.winningTeam == me.team,
                    winner: _result!.winner,
                    reason: _result!.reason,
                    turns: game.turnNumber,
                    onRematch: widget.net == null ? _rematch : null,
                    onMenu: _toMenu,
                  ),
                ),

              if (_error != null)
                Positioned.fill(
                  child: Container(
                    color: const Color(0xE60A0D13),
                    alignment: Alignment.center,
                    child: Panel(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('SOMETHING WENT WRONG', style: titleStyle(22, color: Palette.danger)),
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Text(
                              'The match hit a rules error and stopped.\n$_error',
                              textAlign: TextAlign.center,
                              style: bodyStyle(14, color: Palette.boneDim),
                            ),
                          ),
                          const SizedBox(height: 14),
                          PlateButton(label: 'Back to menu', onPressed: _toMenu),
                        ],
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

  /// Scales a HUD cluster up on big screens; it takes up its scaled size, so taps land everywhere it is drawn.
  static Widget _scaled(double ui, Alignment anchor, Widget child) => ui == 1 ? child : ScaledBox(scale: ui, child: child);

  /// Side chrome steps aside while the combat cards are up.
  Widget _hideInCombat(Widget child) => IgnorePointer(
    ignoring: _combatCovers,
    child: AnimatedOpacity(opacity: _combatCovers ? 0 : 1, duration: const Duration(milliseconds: 220), child: child),
  );

  /// The action buttons' width (every button in the cluster is this wide or narrower).
  static double _actionClusterWidth(bool compact) => compact ? 142.0 : 178.0;

  Widget _actionCluster(Prompt? p, bool boardPick, {bool compact = false}) {
    final children = <Widget>[];
    final btnW = _actionClusterWidth(compact);
    final btnH = compact ? 38.0 : 46.0;
    final fontSz = compact ? 14.5 : 17.0;
    final gap = compact ? 5.0 : 8.0;

    if (p != null && p.ask == Ask.action) {
      final hasScheme = _actions.any((a) => a.kind == ActionKind.scheme);
      final hasAttack = _actions.any((a) => a.kind == ActionKind.attack);
      children.addAll([
        PlateButton(
          key: const ValueKey('hud-maneuver'),
          label: 'Maneuver',
          icon: Icons.directions_run_rounded,
          style: PlateStyle.secondary,
          width: btnW,
          height: btnH,
          fontSize: fontSz,
          onPressed: _startManeuver,
        ),
        SizedBox(height: gap),
        PlateButton(
          key: const ValueKey('hud-scheme'),
          label: 'Scheme',
          icon: Icons.auto_awesome_rounded,
          style: _schemeHint ? PlateStyle.primary : PlateStyle.secondary,
          width: btnW,
          height: btnH,
          fontSize: fontSz,
          onPressed: hasScheme ? _schemes : null,
        ),
        SizedBox(height: gap),
        PlateButton(
          key: const ValueKey('hud-attack'),
          label: _attackMode ? 'Cancel attack' : 'Attack',
          icon: _attackMode ? Icons.close_rounded : Icons.flash_on_rounded,
          style: _attackMode ? PlateStyle.primary : PlateStyle.danger,
          width: btnW,
          height: btnH,
          fontSize: fontSz,
          onPressed: hasAttack ? _toggleAttack : null,
        ),
      ]);
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: children);
    }
    final showSkip = p != null && p.optional && _choiceOverlay(p) == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showSkip) ...[
          PlateButton(
            key: const ValueKey('hud-skip'),
            label: p.skipLabel ?? 'Skip',
            icon: Icons.skip_next_rounded,
            style: PlateStyle.secondary,
            width: _actionClusterWidth(compact),
            height: compact ? 38 : 44,
            fontSize: compact ? 14 : 16,
            onPressed: _skip,
          ),
          SizedBox(height: compact ? 6 : 10),
        ],
        ConfirmHex(
          size: compact ? 56 : 70,
          onPressed: boardPick ? _confirmPending : null,
          tooltip: 'Confirm',
          pulse: boardPick ? _pulse : null,
        ),
      ],
    );
  }

  /// A panel for prompts that can't be answered on the board or from the hand.
  Widget? _choiceOverlay(Prompt p) {
    if (p.ask == Ask.action || _isFighterPrompt || _isBoardSpacePrompt || _isHandCardPrompt || _isPathPrompt) return null;
    final values = _values;
    String? image(Object? v) => v is Card ? v.def.image : null;
    final images = [for (final v in values) image(v)];
    final source = p.source?.def.image;
    if ((p.ask == Ask.card || p.ask == Ask.cards) && images.every((i) => i != null)) {
      return Positioned.fill(
        child: Container(
          color: const Color(0x8C000000),
          child: CardPicker(
            key: ValueKey(p),
            title: p.text,
            images: images.cast<String>(),
            min: p.ask == Ask.cards ? p.min : 1,
            max: p.ask == Ask.cards ? p.max : 1,
            onDone: _submit,
            onSkip: p.optional ? () => _submit(const []) : null,
            skipLabel: p.skipLabel,
            onZoom: (i) => showCardZoom<void>(context, images[i]!),
          ),
        ),
      );
    }
    return Positioned.fill(
      child: Container(
        color: const Color(0x8C000000),
        child: ChoicePanel(
          key: ValueKey(p),
          title: p.text,
          labels: [for (final c in p.choices) c.label],
          source: source,
          onSource: source == null ? null : () => showCardZoom<void>(context, source),
          onPick: (i) => _submit([i]),
          skipLabel: p.skipLabel,
          onSkip: p.optional ? () => _submit(const []) : null,
        ),
      ),
    );
  }
}

/// The other players' plates, stacked: opponents down the right, allies down the left.
class _OpponentColumn extends StatelessWidget {
  const _OpponentColumn({
    super.key,
    required this.players,
    required this.active,
    required this.colorOf,
    required this.me,
    required this.actions,
    required this.compact,
    required this.onTap,
    this.left = false,
  });
  final List<Player> players;
  final Player? active;
  final Color Function(Player) colorOf;
  final Player me;
  final int actions;
  final bool compact;
  final void Function(Player) onTap;

  /// Down the left side (allies): aligned to the left edge.
  final bool left;

  @override
  Widget build(BuildContext context) {
    final plates = [
      for (final o in players)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: compact
              ? _MiniPlate(player: o, color: colorOf(o), active: active == o, ally: o.team == me.team, left: left, onTap: () => onTap(o))
              : PlayerPlate(
                  player: o,
                  color: colorOf(o),
                  subtitle: '${o.team == me.team ? 'Ally · ' : ''}${o.label}',
                  active: active == o,
                  actionsLeft: active == o ? actions : null,
                  showHandBacks: true,
                  onTap: () => onTap(o),
                ),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: plates,
    );
  }
}

class _MiniPlate extends StatelessWidget {
  const _MiniPlate({required this.player, required this.color, required this.active, required this.ally, required this.onTap, this.left = false});
  final Player player;
  final Color color;
  final bool active;
  final bool ally;
  final VoidCallback onTap;
  final bool left;

  static const _e = 40.0, _h = 30.0, _nameW = 74.0;

  /// Its width before UiScale (fixed, so the HUD can keep clear of it).
  static const width = _e * 0.6 + _e * 0.46 + _nameW + 2 * _h + 4; // + the border, both sides

  /// The compact plate (phones, team games): the same parts as PlayerPlate, smaller: the diamond
  /// emblem with the seat number, the name, health and hand on a plate in the hero's colour, and
  /// the companions under it.
  @override
  Widget build(BuildContext context) {
    final heroes = player.heroes.toList();
    final hero = heroes.length == 1 ? player.heroFighter : heroes.first;
    final heroColor = hexColor(player.hero.color);
    final tint = player.eliminated ? Palette.panel : plateColor(heroColor);
    const e = _e, h = _h;
    return Semantics(
      button: true,
      label: '${ally ? 'Ally ' : ''}${player.name}, ${hero.hp} health',
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: player.eliminated ? 0.5 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: width,
                height: e + e * 0.36 * 0.3,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: e * 0.6, top: (e - h) / 2),
                      child: Container(
                        height: h,
                        padding: const EdgeInsets.only(left: e * 0.46),
                        decoration: ShapeDecoration(
                          gradient: LinearGradient(colors: [tint, Color.lerp(tint, Palette.bgDeep, 0.72)!], stops: const [0.25, 1]),
                          shape: ChamferBorder(
                            cut: 6,
                            side: BorderSide(color: active ? Palette.gold : Palette.bone.withValues(alpha: 0.28), width: active ? 1.6 : 1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: _nameW,
                              child: Text(
                                hero.name.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle(12, color: Colors.white, spacing: 0.4),
                              ),
                            ),
                            StatCell(value: hero.defeated ? 0 : hero.hp, size: h, heart: true, low: hero.hp <= 3, tooltip: '${hero.name}: ${hero.hp} health'),
                            StatCell(value: player.hand.length, size: h, icon: Icons.style_rounded, tooltip: 'Cards in hand'),
                          ],
                        ),
                      ),
                    ),
                    HeroEmblem(
                      image: player.hero.avatar,
                      color: readable(heroColor),
                      size: e,
                      seat: player.seat + 1,
                      active: active,
                      grey: player.eliminated,
                    ),
                  ],
                ),
              ),
              if (!player.eliminated)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: SizedBox(
                    width: width - e * 0.12,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      alignment: left ? WrapAlignment.start : WrapAlignment.end,
                      children: [
                        for (final g in CompanionsRow.groups(player)) CompanionChip(group: g, color: readable(color), size: 20),
                        AbilityChip(hero: player.hero, size: 20, iconOnly: true),
                      ],
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

/// Covers the 3D map while its model loads.
class _Board3DCover extends StatelessWidget {
  const _Board3DCover({required this.map, required this.progress});
  final String map;
  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Palette.bgDeep,
    child: Center(
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(map.toUpperCase(), textAlign: TextAlign.center, style: titleStyle(26, spacing: 2)),
            const SizedBox(height: 4),
            Text('Setting up the 3D battlefield…', style: bodyStyle(14, color: Palette.boneDim)),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: v > 0 ? v : null, minHeight: 4, color: Palette.bone, backgroundColor: Palette.line),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Takes every touch and click on the 3D map and forwards it: the web view under it only draws,
/// so HUD buttons on top always get their taps first. One finger or the left button slides the
/// board (and a flick lets it glide on), two fingers pinch to zoom toward their midpoint and twist
/// to turn, the right button orbits, the wheel zooms toward the pointer. Moves are gathered and
/// sent once per frame: a web view's bridge is slow, and the page smooths what it receives.
class _Board3DInput extends StatefulWidget {
  const _Board3DInput({required this.controller});
  final Board3DController controller;

  @override
  State<_Board3DInput> createState() => _Board3DInputState();
}

class _Board3DInputState extends State<_Board3DInput> {
  bool _orbiting = false;
  double _scale = 1;
  double _rotation = 0;
  Size _size = Size.zero;

  // Gathered since the last frame.
  Offset _drag = Offset.zero, _orbit = Offset.zero;
  double _zoom = 1, _twist = 0;
  Offset? _focal;
  bool _flushQueued = false;

  Board3DController get c => widget.controller;

  void _queue() {
    if (_flushQueued) return;
    _flushQueued = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) => _flush());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _flush() {
    _flushQueued = false;
    if (!mounted || _size.isEmpty) return;
    if (_drag != Offset.zero) c.send({'t': 'drag', 'dx': _drag.dx / _size.width, 'dy': _drag.dy / _size.height});
    if (_orbit != Offset.zero) c.send({'t': 'orbit', 'dx': _orbit.dx / _size.width, 'dy': _orbit.dy / _size.height});
    if ((_zoom - 1).abs() > 1e-4 || _twist.abs() > 1e-4) {
      final f = _focal;
      c.send({
        't': 'pinch',
        'k': _zoom,
        'a': _twist,
        if (f != null) 'fx': f.dx / _size.width,
        if (f != null) 'fy': f.dy / _size.height,
      });
    }
    _drag = _orbit = Offset.zero;
    _zoom = 1;
    _twist = 0;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _size = box.biggest;
      return Listener(
        onPointerDown: (e) => _orbiting = e.kind == PointerDeviceKind.mouse && e.buttons & kSecondaryMouseButton != 0,
        onPointerMove: (e) {
          if (!_orbiting) return;
          _orbit += e.delta;
          _queue();
        },
        onPointerUp: (_) => _orbiting = false,
        onPointerCancel: (_) => _orbiting = false,
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent || e.scrollDelta.dy == 0) return;
          // A notch is ~100 px: about 12% per notch, finer for a trackpad's small steps.
          _zoom *= math.exp(-e.scrollDelta.dy.clamp(-300.0, 300.0) / 800);
          _focal = e.localPosition;
          _queue();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => c.send({'t': 'pick', 'x': d.localPosition.dx / _size.width, 'y': d.localPosition.dy / _size.height}),
          onScaleStart: (_) {
            _scale = 1;
            _rotation = 0;
          },
          onScaleUpdate: (d) {
            if (_orbiting) return;
            _drag += d.focalPointDelta;
            if (d.pointerCount > 1) {
              _zoom *= d.scale / _scale;
              _twist += d.rotation - _rotation;
              _scale = d.scale;
              _rotation = d.rotation;
              _focal = d.localFocalPoint;
            }
            _queue();
          },
          onScaleEnd: (d) {
            // Only when the last finger lifts (going from two fingers to one isn't a flick).
            if (_orbiting || d.pointerCount > 0) return;
            _flush();
            final v = d.velocity.pixelsPerSecond;
            if (v.distance < 120) return;
            c.send({'t': 'fling', 'vx': v.dx / _size.width, 'vy': v.dy / _size.height});
          },
        ),
      );
    },
  );
}

/// The board camera's zoom: the scale along the board's x axis. (`getMaxScaleOnAxis` also counts
/// the depth axis; a matrix scaled in x and y only reads as 1 there, which sent every camera move
/// on a big board, where the fit is below 1x, to 1x: far too close.)
double _planeScale(Matrix4 m) => math.sqrt(m.storage[0] * m.storage[0] + m.storage[1] * m.storage[1]);

/// A 2D camera move that zooms at an even pace (log scale) while the board point at [anchor]
/// travels in a straight line. A plain matrix tween lerps scale and offset separately, which
/// swings the board sideways through a push-in; with the anchor on a fixed point (the pointer for
/// the wheel) that point stays exactly put.
class _CamTween extends Animatable<Matrix4> {
  _CamTween(Matrix4 begin, Matrix4 end, this.anchor)
    : _s0 = _planeScale(begin),
      _s1 = _planeScale(end),
      _c0 = _sceneAt(begin, anchor),
      _c1 = _sceneAt(end, anchor);

  final Offset anchor;
  final double _s0, _s1;
  final Offset _c0, _c1;

  static Offset _sceneAt(Matrix4 m, Offset screen) {
    final t = m.getTranslation(), s = _planeScale(m);
    return Offset((screen.dx - t.x) / s, (screen.dy - t.y) / s);
  }

  @override
  Matrix4 transform(double t) {
    final s = _s0 * math.pow(_s1 / _s0, t);
    final c = Offset.lerp(_c0, _c1, t)!;
    return Matrix4.identity()
      ..translateByDouble(anchor.dx - c.dx * s, anchor.dy - c.dy * s, 0, 1)
      ..scaleByDouble(s, s, s, 1);
  }
}
