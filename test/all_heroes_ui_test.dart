// Every hero, played to the end through the real match screen. You are each hero once (against
// the next hero in the list, played by the AI), so every hero is also met once as an opponent.
// Every prompt you get is answered the way a player answers it: MANEUVER / SCHEME / ATTACK and
// SKIP buttons, tapping the target and attacker on the board, the hand card, the space, fighter
// or path on the board (panning the board first when the spot is off screen or under the HUD),
// the card picker and the option panel. What to pick is up to an AI; how it is picked is the
// UI's job, and the test fails when a prompt can't be answered that way, when the UI answers
// something else than what was tapped, or when the match stops with an error.
//
// `--dart-define=SHARD=2/4` runs every 4th hero from the 3rd; `--dart-define=HEROES=a,b` only
// those heroes.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card, Intent;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/engine/state.dart';
import 'package:unmatched_game/main.dart';
import 'package:unmatched_game/ui/match/hud.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/match/match_screen.dart';

import 'support.dart' show loadData;
import 'widget_test.dart' show loadFonts, makeServices, phone, desktop, smallPhone;

const _shard = String.fromEnvironment('SHARD');
const _only = String.fromEnvironment('HEROES');

void main() {
  setUpAll(loadFonts);

  final data = loadData();
  final all = data.heroes.keys.where(isImplemented).toList()..sort();
  final maps = data.mapsFor('1v1')..sort((a, b) => a.id.compareTo(b.id));
  final sizes = [phone, desktop, smallPhone];
  final (part, parts) = _shard.isEmpty ? (1, 1) : (int.parse(_shard.split('/')[0]), int.parse(_shard.split('/')[1]));
  final only = _only.isEmpty ? null : _only.split(',').toSet();

  for (var i = 0; i < all.length; i++) {
    if (i % parts != part - 1 || (only != null && !only.contains(all[i]))) continue;
    final hero = all[i], foe = all[(i + 1) % all.length];
    final size = sizes[i % sizes.length], map = maps[i % maps.length];
    testWidgets('$hero plays a whole match through the UI against $foe (${map.id}, ${size.width.round()} wide)', (t) async {
      final s = makeServices(speed: 0.1);
      await t.runAsync(() => s.loadData());
      t.view.physicalSize = size * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final config = MatchConfig(mode: GameMode.duel, players: 2, map: s.data.maps[map.id]!, ai: AiLevel.medium, heroIds: [hero, foe]);
      await t.pumpWidget(UnmatchedApp(services: s, home: MatchScreen(config: config, seed: i + 1)));
      final d = _Driver(t, size, AiAgent(level: AiLevel.medium, seed: i));
      Prompt? last;
      var frame = 0;
      for (; frame < 40000 && find.byType(ResultView).evaluate().isEmpty; frame++) {
        await t.pump(const Duration(milliseconds: 20));
        final error = d.state.debugError as String?;
        if (error != null) fail('$hero v $foe: the match stopped: $error\n${d.recent}');
        final p = d.state.debugPrompt as Prompt?;
        if (p == null || p == last) continue;
        // Look before tapping, as a player does: let the camera and the banners settle.
        await t.pump(const Duration(milliseconds: 300));
        if (d.state.debugPrompt != p) continue;
        last = p;
        await d.answer(p);
      }
      // ignore: avoid_print
      print('$hero v $foe: ${d.summary}');
      expect(find.byType(ResultView), findsOneWidget, reason: '$hero v $foe did not finish in $frame frames\n${d.recent}');
      expect(d.problems, isEmpty, reason: '$hero v $foe:\n${d.problems.join('\n')}');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 30));
    }, timeout: const Timeout(Duration(minutes: 12)));
  }
}

class _Driver {
  _Driver(this.t, this.size, this.ai);
  final WidgetTester t;
  final Size size;
  final AiAgent ai;

  final problems = <String>[];
  final counts = <String, int>{};
  final _log = <String>[];
  var panned = 0, covered = 0;

  dynamic get state => t.state(find.byType(MatchScreen));
  Game get game => state.game as Game;
  Player get me => state.me as Player;
  Rect get screen => (Offset.zero & size).deflate(2);

  String get summary =>
      '${counts.entries.map((e) => '${e.key} ${e.value}').join(', ')}; panned $panned, under the HUD $covered';
  String get recent => _log.reversed.take(12).toList().reversed.join('\n');

  bool _done(Prompt p) => state.debugPrompt != p;

  /// Answers [p] through the UI with what the AI picks; falls back to answering directly (and
  /// records the problem) when the UI can't.
  Future<void> answer(Prompt p) async {
    final picks = await ai.decide(game, p);
    final kind = _kind(p, picks);
    counts.update(kind, (n) => n + 1, ifAbsent: () => 1);
    _log.add('[$kind] ${p.text} -> $picks');
    final how = await _perform(p, picks, kind);
    for (var i = 0; i < 5 && !_done(p); i++) {
      await t.pump(const Duration(milliseconds: 30));
    }
    if (!_done(p)) {
      if (how != 'covered') problems.add('[$kind] "${p.text}": the UI did not answer it ($how)');
      // A dialog left open (zoomed card, confirm) would swallow the next taps.
      await _closeDialogs();
      if (state.debugPrompt == p) state.debugAnswer(picks);
      return;
    }
    final got = state.debugLastPicks as List<int>?;
    final same = got != null && got.length == picks.length && (got.toSet().containsAll(picks));
    if (!same) problems.add('[$kind] "${p.text}": tapped for $picks, the UI answered $got');
  }

  String _kind(Prompt p, List<int> picks) {
    final vs = [for (final c in p.choices) c.value];
    if (p.ask == Ask.action) {
      if (picks.isEmpty) return 'action skip';
      return 'action ${(vs[picks.first] as ActionChoice).kind.name}';
    }
    if (picks.isEmpty) return '${p.ask.name} skip';
    return p.ask.name;
  }

  Future<String> _perform(Prompt p, List<int> picks, String kind) async {
    final vs = [for (final c in p.choices) c.value];
    final overlay = find.byType(ChoicePanel).evaluate().isNotEmpty || find.byType(CardPicker).evaluate().isNotEmpty;
    if (find.byType(CardPicker).evaluate().isNotEmpty) return _cardPicker(p, picks);
    if (find.byType(ChoicePanel).evaluate().isNotEmpty) {
      return await _tapKey(ValueKey(picks.isEmpty ? 'choice-skip' : 'choice-${picks.first}')) ? 'choice panel' : 'no option button';
    }
    if (picks.isEmpty) {
      return !overlay && await _tapKey(const ValueKey('hud-skip')) ? 'skip' : 'no skip button';
    }
    final v = vs[picks.first];
    if (p.ask == Ask.action) {
      final a = v as ActionChoice;
      switch (a.kind) {
        case ActionKind.maneuver:
          return await _tapKey(const ValueKey('hud-maneuver')) ? 'maneuver' : 'no maneuver button';
        case ActionKind.scheme:
          if (!await _tapHandCard(a.card!)) return 'scheme card not reachable in the hand';
          return await _tapText('PLAY THIS SCHEME') ? 'scheme' : 'no play button';
        case ActionKind.attack:
          if (!await _tapKey(const ValueKey('hud-attack'))) return 'no attack button';
          if (!await _tapFighter(a.target!)) return 'covered';
          if (state.debugPrompt == p && find.text('ATTACK').evaluate().isEmpty) {
            // Several of your fighters can attack it: now the attacker.
            if (!await _tapFighter(a.fighter!)) return 'covered';
          }
          if (find.text('ATTACK').evaluate().isNotEmpty) await _tapText('ATTACK');
          return 'attack';
      }
    }
    if (v is Card && me.hand.contains(v) && p.ask == Ask.card) {
      if (!await _tapHandCard(v)) return 'card not reachable in the hand';
      if (find.text('ATTACK WITH THIS CARD').evaluate().isNotEmpty) await _tapText('ATTACK WITH THIS CARD');
      return 'hand card';
    }
    if (p.ask == Ask.fighter && v is Fighter && v.onBoard) return await _tapFighter(v) ? 'fighter' : 'covered';
    if (p.ask == Ask.space) {
      final space = v is int ? v : (v is Token ? v.space : null);
      if (space != null) return await _tapSpace(space) ? 'space' : 'covered';
    }
    if (p.ask == Ask.path && v is (int, int)) return await _tapAt(() => state.debugEdgeOnScreen(v) as Offset?) ? 'path' : 'covered';
    return 'no way to answer ${p.ask.name} with ${v.runtimeType}';
  }

  // ------------------------------------------------------------------ board

  Future<bool> _tapSpace(int id) => _tapAt(() {
    final r = state.debugSpaceOnScreen(id) as (Offset, double)?;
    // A little off the centre, where a finger lands (and where fog clouds are drawn).
    return r == null ? null : r.$1 + Offset(r.$2 * 0.2, -r.$2 * 0.25);
  });

  Future<bool> _tapFighter(Fighter f) => _tapAt(() => state.debugFighterOnScreen(f) as Offset?);

  bool _reachable(Offset? at) => at != null && screen.contains(at) && (state.debugTapReachesBoard(at) as bool);

  /// Taps a spot on the board; when it's off screen or under the HUD, drags the board to bring
  /// it to the middle first, as a player would.
  Future<bool> _tapAt(Offset? Function() where) async {
    var at = where();
    if (!_reachable(at)) {
      if (at == null) return false;
      final centre = size.center(Offset.zero);
      // Grab the board somewhere free of the HUD, near the middle.
      Offset? grab;
      for (final o in [Offset.zero, const Offset(0, -40), const Offset(60, 0), const Offset(-60, 0), const Offset(0, 50)]) {
        if (_reachable(centre + o)) {
          grab = centre + o;
          break;
        }
      }
      if (grab == null) {
        covered++;
        return false;
      }
      final g = await t.startGesture(grab, kind: PointerDeviceKind.touch);
      final delta = centre - at;
      const steps = 12;
      for (var i = 0; i < steps; i++) {
        await g.moveBy(delta / steps.toDouble());
        await t.pump(const Duration(milliseconds: 16));
      }
      // Hold still before lifting, so the drag doesn't fling.
      await t.pump(const Duration(milliseconds: 120));
      await g.up();
      await t.pump(const Duration(milliseconds: 200));
      panned++;
      at = where();
      if (!_reachable(at)) {
        covered++;
        return false;
      }
    }
    await t.tapAt(at!);
    await t.pump(const Duration(milliseconds: 40));
    return true;
  }

  // ------------------------------------------------------------------ HUD

  /// Taps the part of [f] that is on top (hand cards overlap), if any of it is.
  Future<bool> _tapVisible(Finder f) async {
    if (f.evaluate().isEmpty) return false;
    final target = f.evaluate().first.renderObject;
    final r = t.getRect(f.first);
    for (final fy in const [0.5, 0.3, 0.7, 0.15, 0.85]) {
      for (final fx in const [0.5, 0.3, 0.15, 0.7, 0.85, 0.05]) {
        final at = Offset(r.left + r.width * fx, r.top + r.height * fy);
        if (!screen.contains(at)) continue;
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, at, t.view.viewId);
        bool inside(HitTestEntry e) {
          for (Object? o = e.target; o is RenderObject; o = o.parent) {
            if (o == target) return true;
          }
          return false;
        }

        // The first opaque thing hit must be part of the widget.
        final first = hit.path.firstWhere((e) => e.target is RenderBox, orElse: () => hit.path.first);
        if (!inside(first)) continue;
        await t.tapAt(at);
        await t.pump(const Duration(milliseconds: 60));
        // Dialogs open with a short transition.
        await t.pump(const Duration(milliseconds: 220));
        return true;
      }
    }
    return false;
  }

  Future<bool> _tapKey(Key k) async {
    final f = find.byKey(k);
    if (f.evaluate().isEmpty) return false;
    await t.ensureVisible(f.first);
    await t.pump(const Duration(milliseconds: 20));
    return _tapVisible(f);
  }

  Future<bool> _tapText(String s) => _tapVisible(find.text(s).last);

  Future<bool> _tapHandCard(Card c) => _tapVisible(find.byKey(ValueKey(c.uid)));

  Future<String> _cardPicker(Prompt p, List<int> picks) async {
    if (picks.isEmpty) return await _tapKey(const ValueKey('pick-skip')) ? 'picker skip' : 'no skip in the card picker';
    final list = find.descendant(of: find.byType(CardPicker), matching: find.byType(Scrollable)).first;
    for (final i in picks) {
      final item = find.byKey(ValueKey('pick-$i'));
      // Bring the card into view: back to the start of the row, then along it.
      if (!_onScreen(item)) await t.drag(list, const Offset(4000, 0));
      for (var n = 0; n < 40 && !_onScreen(item); n++) {
        await t.drag(list, const Offset(-120, 0));
        await t.pump(const Duration(milliseconds: 20));
      }
      if (!await _tapVisible(item)) return 'card $i not reachable in the card picker';
      if (_done(p)) return 'card picker';
    }
    return await _tapKey(const ValueKey('pick-confirm')) ? 'card picker' : 'no confirm in the card picker';
  }

  bool _onScreen(Finder f) {
    if (f.evaluate().isEmpty) return false;
    final r = t.getRect(f.first);
    return screen.contains(r.center) && screen.contains(r.topLeft + const Offset(4, 4)) && screen.contains(r.bottomRight - const Offset(4, 4));
  }

  Future<void> _closeDialogs() async {
    for (var i = 0; i < 3 && find.byType(ModalBarrier).evaluate().length > 1; i++) {
      final nav = t.state<NavigatorState>(find.byType(Navigator).last);
      nav.maybePop();
      await t.pump(const Duration(milliseconds: 300));
    }
  }
}
