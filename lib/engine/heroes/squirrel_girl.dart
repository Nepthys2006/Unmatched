/// Marvel Teen Spirit: Squirrel Girl and her squirrels (small fighters).
library;

import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

/// GO NUTS! At the start of your turn, (you may) summon a squirrel in an empty space adjacent to
/// Squirrel Girl. The 8 squirrels start off the board. Squirrels are small fighters: see
/// [Game.canOccupy] and [Game.damage].
class SquirrelGirl extends HeroScript {
  Fighter get sg => me.heroFighter;
  Iterable<Fighter> get squirrels => me.fighters.where((f) => f.id == 'squirrel');
  Iterable<Fighter> get onBoardSquirrels => squirrels.where((f) => f.onBoard);

  @override
  bool startsInReserve(Fighter f) => f.isSidekick;

  @override
  bool isSmall(Fighter f) => f.owner == me && f.id == 'squirrel';

  @override
  List<String> status() => ['${onBoardSquirrels.length} squirrels'];

  @override
  List<String> reference() => const [
        'Squirrels are small fighters: up to 4 share a space, also with one other fighter, and are adjacent to fighters in their space.',
        'Opposing fighters move through squirrels, and squirrels move through opposing fighters.',
        'Damage to a squirrel is taken by every squirrel in its space.',
        'Summoning: an empty space next to Squirrel Girl; if all 8 are out, move one of them there.',
      ];

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || !sg.onBoard) return;
    await summonSquirrel(g.board.neighbours(sg.space!), optional: true, text: 'Go Nuts!: summon a squirrel next to Squirrel Girl');
  }

  /// Summoning rules: a squirrel off the board goes into one of [spaces] (empty ones, or any it
  /// may share when [shared]); if all 8 are on the board, one of them moves there instead.
  Future<bool> summonSquirrel(Iterable<int> spaces, {bool optional = false, bool shared = false, String? text}) async {
    final g = game;
    final opts = spaces.where((s) => shared ? g.canOccupy(squirrels.first, s, ignoreSelf: false) : g.isEmpty(s)).toSet().toList();
    if (opts.isEmpty) return false;
    final spare = squirrels.where((f) => !f.onBoard && !f.offBoard).firstOrNull;
    var f = spare;
    if (f == null) {
      f = await g.chooseFighter(me, onBoardSquirrels, 'All squirrels are on the board: choose one to move',
          intent: Intent.moveOwn, optional: optional);
      if (f == null) return false;
    }
    final s = await g.chooseSpace(me, opts, text ?? 'Summon a squirrel', intent: Intent.moveOwn, subject: f, optional: optional && spare != null);
    if (s == null) return false;
    if (spare != null) return g.revive(f, s);
    if (s == f.space) return true;
    await g.placeOn(f, s); // placed like any placement (traps, "when a fighter moves")
    return true;
  }

  /// Squirrels adjacent to [f] (including those sharing its space).
  int squirrelsAdjacentTo(Fighter f) => onBoardSquirrels.where((q) => game.adjacent(q, f)).length;

  /// Squirrels adjacent to a space: in a neighbouring space or in the space itself.
  int squirrelsAdjacentToSpace(int s) =>
      onBoardSquirrels.where((q) => q.space == s || game.board.adjacent(q.space!, s)).length;

  int squirrelsInZoneOf(Fighter f) => onBoardSquirrels.where((q) => game.sameZone(q, f)).length;

  /// Squirgility: up to [n] spaces, through sidekicks; spaces with sidekicks cost no movement.
  Map<int, List<int>> squirgilityRoutes(Fighter f, int n) {
    final g = game;
    bool hasSidekick(int s) => g.fightersAt(s).any((o) => o.isSidekick && o != f);
    bool blocked(int s) => g.fightersAt(s).any((o) => o != f && o.isEnemyOf(me) && !o.isSmall && !o.isSidekick);
    final cost = <int, int>{f.space!: 0};
    final paths = <int, List<int>>{f.space!: [f.space!]};
    final queue = [f.space!];
    while (queue.isNotEmpty) {
      queue.sort((a, b) => cost[a]!.compareTo(cost[b]!));
      final s = queue.removeAt(0);
      for (final nb in g.board.neighbours(s)) {
        if (blocked(nb)) continue;
        final c = cost[s]! + (hasSidekick(nb) ? 0 : 1);
        if (c > n) continue;
        final cur = cost[nb];
        if (cur != null && (cur < c || (cur == c && paths[nb]!.length <= paths[s]!.length + 1))) continue;
        cost[nb] = c;
        paths[nb] = [...paths[s]!, nb];
        if (!queue.contains(nb)) queue.add(nb);
      }
    }
    return {
      for (final e in paths.entries)
        if (e.key == f.space || g.canOccupy(f, e.key)) e.key: e.value
    };
  }

  @override
  Map<String, CardScript> get cards => {
    'EAT NUTS': CardScript(effect: (x) async {
      await x.heal(sg, 2);
      if (sg.onBoard) await summonSquirrel(x.board.neighbours(sg.space!), text: 'Eat Nuts: summon a squirrel next to Squirrel Girl');
    }),
    'HORDE OF SQUIRRELS': CardScript(effect: (x) async {
      final targets = x.game.onBoard.where((f) => f.spaces.any((s) => squirrelsAdjacentToSpace(s) >= 4)).toList();
      final f = await x.chooseFighter(targets, 'Horde of Squirrels: deal 2 damage to a fighter in a space with 4+ squirrels next to it',
          intent: Intent.harm);
      if (f != null) await x.damage(f, 2);
    }),
    'SQUIRMISH': CardScript(after: (x) async {
      if (!sg.onBoard) return;
      await summonSquirrel([sg.space!], shared: true, text: "Squirmish: summon a squirrel in Squirrel Girl's space");
      if (sg.onBoard) await x.place(sg, x.zoneSpaces(sg), text: 'Squirmish: place Squirrel Girl in any space in her zone');
    }),
    "GET 'EM TIPPY-TOE!": CardScript(after: (x) async {
      for (var i = 1; i <= 2; i++) {
        await summonSquirrel(x.allSpaces, text: "Get 'Em Tippy-Toe!: summon a squirrel ($i of 2)");
      }
    }),
    'SQUIRGILITY': CardScript(after: (x) async {
      if (!sg.onBoard) return;
      await x.game.moveFighter(sg, 3, chooser: x.me, source: x.card, routes: squirgilityRoutes(sg, 3),
          text: 'Squirgility: move Squirrel Girl up to 3 (sidekick spaces are free)');
    }),
    'BITE OF STEEL': valueIf((x) => squirrelsInZoneOf(x.oppFighter) >= 4, 5),
    'CALL OF THE MILD': CardScript(
      during: (x) async {
        if (squirrelsInZoneOf(x.fighter) >= 4) x.setValue(4);
      },
      after: (x) async {
        if (x.won) await x.draw(2);
      },
    ),
    'FUZZBALL SPECIAL': CardScript(after: (x) => moveEach(x, onBoardSquirrels, 3)),
    'KICK BUTTS': CardScript(during: (x) async {
      final n = squirrelsAdjacentTo(x.oppFighter);
      if (n > 0) x.addValue(n, '$n squirrel${n == 1 ? '' : 's'} adjacent');
    }),
    'NUTWORK OF SPIES': CardScript(effect: (x) async {
      final t = x.opp;
      final n = t.onBoard.any((f) => squirrelsAdjacentTo(f) >= 4) ? 2 : 1;
      if (await x.game.lookAtHand(x.me, t)) await x.discard(t, n, chooser: x.me);
    }),
    'UNBEATABLE SQUIRREL GIRL': CardScript(immediately: (x) async {
      if (squirrelsAdjacentTo(x.oppFighter) < 4) return;
      x.cancelOpponent();
      x.ignoreOpponentValue();
    }),
  };
}
