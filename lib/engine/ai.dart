/// A rules-following computer opponent. It answers the same prompts a human does, judging each
/// choice from the prompt's [Intent] and the visible state (it never peeks at hidden cards it
/// hasn't legitimately seen).
library;

import 'dart:math';

import 'combat.dart';
import 'game.dart';
import 'prompt.dart';
import 'state.dart';

enum AiLevel { easy, medium, hard, insane }

class AiAgent implements Agent {
  AiAgent({this.level = AiLevel.medium, int? seed}) : _rng = Random(seed);

  final AiLevel level;
  final Random _rng;

  double get _noise => switch (level) { AiLevel.easy => 3.0, AiLevel.medium => 0.9, AiLevel.hard => 0.3, AiLevel.insane => 0.05 };
  double _jitter() => (_rng.nextDouble() - 0.5) * _noise;

  @override
  Future<List<int>> decide(Game g, Prompt p) async {
    final r = _decide(g, p);
    return r;
  }

  List<int> _decide(Game g, Prompt p) {
    final n = p.choices.length;
    if (n == 0) return const [];
    switch (p.ask) {
      case Ask.action:
        return [_best(n, (i) => _actionScore(g, p.player, p.choices[i].value as ActionChoice))];
      case Ask.yesNo:
        final yes = switch (p.intent) { Intent.harm => false, Intent.none => _rng.nextBool(), _ => true };
        return [yes ? 0 : 1];
      case Ask.option:
        return [p.intent == Intent.none ? _rng.nextInt(n) : 0];
      case Ask.number:
        return [n - 1];
      case Ask.cards:
        return _pickCards(g, p);
      case Ask.card:
        return _pickCard(g, p);
      case Ask.fighter:
        return _pickFighter(g, p);
      case Ask.space:
        return _pickSpace(g, p);
      case Ask.path:
        // Foot soldiers: as close to opposing fighters as possible.
        return [
          _best(n, (i) {
            final (a, b) = p.choices[i].value as (int, int);
            var d = 99;
            for (final e in g.enemyFighters(p.player)) {
              d = min(d, min(g.board.distance(a, e.space!), g.board.distance(b, e.space!)));
            }
            return -d.toDouble();
          })
        ];
    }
  }

  int _best(int n, double Function(int i) score) {
    var best = 0;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < n; i++) {
      final s = score(i) + _jitter();
      if (s > bestScore) {
        bestScore = s;
        best = i;
      }
    }
    return best;
  }

  // ------------------------------------------------------------------------------- cards

  /// How useful a card is to keep in hand.
  double worth(Card c) {
    final t = c.def.text.values.join(' ').toLowerCase();
    var w = (c.def.value ?? 2).toDouble() + (c.def.boost ?? 0) * 0.35;
    if (t.contains('draw')) w += 0.8;
    if (t.contains('damage')) w += 1.0;
    if (t.contains('cancel')) w += 0.9;
    if (t.contains('gain 1 action') || t.contains('gain 2 actions')) w += 1.0;
    if (t.contains('recover')) w += 0.5;
    if (c.def.isScheme) w += 1.2;
    return w;
  }

  double _effectBonus(Card c, {required bool attacking}) {
    final t = c.def.text.values.join(' ').toLowerCase();
    var b = 0.0;
    if (t.contains('draw')) b += 0.6;
    if (t.contains('damage')) b += attacking ? 1.0 : 0.6;
    if (t.contains('cancel')) b += attacking ? 0.4 : 1.2;
    if (t.contains('boost this')) b += 1.5;
    if (t.contains('gain 1 action')) b += attacking ? 1.0 : 0.0;
    if (t.contains('prevent all damage')) b += attacking ? 0 : 4;
    return b;
  }

  int _estimatedValue(Game g, Combat c, Side s, Card card) {
    final old = s.card;
    s.card = card;
    final v = g.valueOf(s).total;
    s.card = old;
    return v;
  }

  List<int> _pickCard(Game g, Prompt p) {
    final cards = [for (final ch in p.choices) ch.value as Card];
    switch (p.intent) {
      case Intent.attackCard:
        final c = p.subject as Combat;
        final defHand = c.defender.player.hand.length;
        return [
          _best(cards.length, (i) {
            final v = _estimatedValue(g, c, c.attacker, cards[i]);
            final kill = defHand == 0 && v >= c.defender.fighter.hp ? 4 : 0;
            return v + _effectBonus(cards[i], attacking: true) + kill - worth(cards[i]) * 0.15;
          })
        ];
      case Intent.defenseCard:
        final c = p.subject as Combat;
        final threat = _expectedAttack(g, c);
        var bestI = -1;
        var bestS = 0.0;
        for (var i = 0; i < cards.length; i++) {
          final v = _estimatedValue(g, c, c.defender, cards[i]);
          final saved = min(v, threat).toDouble();
          final s = saved + _effectBonus(cards[i], attacking: false) - worth(cards[i]) * 0.25 + _jitter();
          if (s > bestS) {
            bestS = s;
            bestI = i;
          }
        }
        // Always defend when the hit could be lethal.
        if (bestI < 0 && threat >= c.defender.fighter.hp) bestI = _best(cards.length, (i) => (cards[i].def.value ?? 0).toDouble());
        if (bestI < 0 && p.optional) return const [];
        return [max(0, bestI)];
      case Intent.boost:
        if (p.optional && p.player.hand.length < 3) return const [];
        final i = _best(cards.length, (i) => (cards[i].def.boost ?? 0) * 1.2 - worth(cards[i]));
        if (p.optional && (cards[i].def.boost ?? 0) < 2 && _rng.nextBool()) return const [];
        return [i];
      case Intent.loseOwn:
        return [_best(cards.length, (i) => -worth(cards[i]))];
      case Intent.loseEnemy:
        return [_best(cards.length, (i) => worth(cards[i]))];
      case Intent.forceEnemy:
        return [_best(cards.length, (i) => -(cards[i].def.value ?? 0) - _effectBonus(cards[i], attacking: true))];
      default:
        if (p.optional && _rng.nextDouble() < 0.15) return const [];
        return [_best(cards.length, (i) => worth(cards[i]))];
    }
  }

  int _expectedAttack(Game g, Combat c) {
    final known = c.attacker.player.hand.isEmpty ? 0 : 4;
    return known + (c.attacker.ops.fold(0, (a, o) => a + (o.isSet ? 0 : o.amount)));
  }

  List<int> _pickCards(Game g, Prompt p) {
    final cards = [for (final ch in p.choices) ch.value as Card];
    final order = List.generate(cards.length, (i) => i);
    if (p.intent == Intent.boost) {
      // "Discard any number to add value": throw in the cheap cards, keep at least two.
      final cheap = order.where((i) => worth(cards[i]) < 3.2).toList();
      final keep = max(0, p.player.hand.length - 2);
      return cheap.take(min(keep, p.max)).toList();
    }
    final lose = p.intent == Intent.loseOwn || p.intent == Intent.none;
    order.sort((a, b) => lose ? worth(cards[a]).compareTo(worth(cards[b])) : worth(cards[b]).compareTo(worth(cards[a])));
    final k = p.intent == Intent.gainOwn ? p.max : p.min;
    return order.take(max(k, p.min)).toList();
  }

  // ---------------------------------------------------------------------------- fighters

  List<int> _pickFighter(Game g, Prompt p) {
    final fs = [for (final ch in p.choices) ch.value as Fighter];
    final me = p.player;
    switch (p.intent) {
      case Intent.harm:
        final i = _best(fs.length, (i) {
          final f = fs[i];
          final enemy = f.isEnemyOf(me);
          var s = enemy ? 10.0 : -10.0;
          if (enemy) {
            s += f.isHero ? 2 : 0;
            s += f.hp <= 2 ? 4 : 0;
          } else {
            s += f.isHero ? -5 : 0;
          }
          return s;
        });
        if (p.optional && fs[i].isFriendOf(me)) return const [];
        return [i];
      case Intent.help:
        return [_best(fs.length, (i) => (fs[i].isFriendOf(me) ? 10 : -10) + (fs[i].maxHp - fs[i].hp) + (fs[i].isHero ? 1 : 0))];
      case Intent.attackTarget:
        return [_best(fs.length, (i) => (fs[i].isHero ? 3 : 0) - fs[i].hp * 0.2)];
      default:
        return [0];
    }
  }

  // ------------------------------------------------------------------------------ spaces

  List<int> _pickSpace(Game g, Prompt p) {
    // Choosing a token (e.g. which fog to move).
    if (p.choices.first.value is Token) return [_rng.nextInt(p.choices.length)];
    final spaces = [for (final ch in p.choices) ch.value as int];
    if (p.subject is Token) {
      // Fog: its owner wants it near their hero, the opponent wants it far away.
      final t = p.subject as Token;
      final hero = t.owner.heroFighter;
      final own = t.owner.isAllyOf(p.player);
      return [
        _best(spaces.length, (i) {
          if (!hero.onBoard) return 0;
          final d = g.board.distance(spaces[i], hero.space!).toDouble();
          return own ? -d : d;
        })
      ];
    }
    final f = p.subject is Fighter ? p.subject as Fighter : null;
    if (f != null) {
      final own = f.isFriendOf(p.player);
      final i = _best(spaces.length, (i) => own ? ownSpaceScore(g, f, spaces[i]) : -enemySpaceThreat(g, f, spaces[i], p.player));
      return [i];
    }
    if (p.intent == Intent.harm) {
      return [
        _best(spaces.length, (i) {
          final s = spaces[i];
          var score = 0.0;
          final at = g.fighterAt(s);
          if (at != null) score += at.isFriendOf(p.player) ? -6 : 6;
          for (final n in g.board.neighbours(s)) {
            final o = g.fighterAt(n);
            if (o != null) score += o.isFriendOf(p.player) ? -1 : 1.5;
          }
          return score;
        })
      ];
    }
    return [_rng.nextInt(spaces.length)];
  }

  /// How good space [s] is for my fighter [f].
  double ownSpaceScore(Game g, Fighter f, int s) {
    final foes = g.enemyFighters(f.owner).toList();
    final foeHero = foes.where((e) => e.isHero).map((e) => e.hp).fold(0, max);
    var score = 0.0;
    final healthy = f.hp >= 6 || f.isSidekick || f.hp >= foeHero;
    final cards = f.owner.hand.where((c) => g.canAttackWith(c, f)).length;
    for (final e in foes) {
      final d = g.board.distance(s, e.space!);
      final adj = g.board.adjacent(s, e.space!);
      final canHit = adj || (f.isRanged && g.board.sharesZone(s, e.space!));
      final weight = e.isHero ? 1.0 : 0.45;
      if (canHit && cards > 0) score += 5 * weight;
      if (healthy || f.isSidekick) {
        score -= d * (f.isRanged ? 0.25 : 0.8) * weight;
      } else {
        score += min(d, 4) * 0.6 * weight;
      }
      final threatens = adj || (e.isRanged && g.board.sharesZone(s, e.space!));
      if (threatens) score -= (healthy ? 0.8 : 3.0) * (e.isHero ? 1 : 0.6);
    }
    return score;
  }

  /// How dangerous opposing fighter [f] would be to [me] in space [s].
  double enemySpaceThreat(Game g, Fighter f, int s, Player me) {
    var t = 0.0;
    for (final m in g.onBoard.where((m) => m.isFriendOf(me))) {
      final adj = g.board.adjacent(s, m.space!);
      if (adj || (f.isRanged && g.board.sharesZone(s, m.space!))) t += m.isHero ? 4 : 1.5;
      t -= g.board.distance(s, m.space!) * 0.2;
    }
    return t;
  }

  // ----------------------------------------------------------------------------- actions

  double _actionScore(Game g, Player me, ActionChoice a) {
    switch (a.kind) {
      case ActionKind.attack:
        final f = a.fighter!, t = a.target!;
        final cards = me.hand.where((c) => g.canAttackWith(c, f)).toList();
        var best = 0.0;
        for (final c in cards) {
          best = max(best, (c.def.value ?? 0) + _effectBonus(c, attacking: true));
        }
        final defense = t.owner.hand.isEmpty ? 0.0 : 2.8;
        var s = best - defense + 1.2;
        if (t.isHero) s += 1.5;
        if (t.hp <= best - defense) s += t.isHero ? 20 : 3;
        if (me.hand.length <= 1) s -= 1.5;
        return s;
      case ActionKind.scheme:
        final c = a.card!;
        final t = c.def.text.values.join(' ').toLowerCase();
        var s = 2.4;
        if (t.contains('draw')) s += 0.8;
        if (t.contains('gain') && t.contains('action')) s += 1.2;
        if (t.contains('damage')) s += 1.2;
        if (t.contains('recover')) s += me.heroFighter.hp < me.heroFighter.maxHp - 3 ? 1.5 : -1.0;
        return s;
      case ActionKind.maneuver:
        var s = 1.6;
        if (me.hand.length <= 2) s += 1.6;
        final canAttack = g.legalActions(me).any((x) => x.kind == ActionKind.attack);
        if (!canAttack) s += 2.0;
        if (me.deck.isEmpty) s -= 6;
        return s;
    }
  }
}

/// Picks uniformly among legal choices. Used by the fuzz tests to reach odd corners.
class RandomAgent implements Agent {
  RandomAgent([int? seed]) : _rng = Random(seed);
  final Random _rng;

  @override
  Future<List<int>> decide(Game g, Prompt p) async {
    final n = p.choices.length;
    if (n == 0) return const [];
    if (p.ask == Ask.cards) {
      final k = p.min + _rng.nextInt(p.max - p.min + 1);
      return (List.generate(n, (i) => i)..shuffle(_rng)).take(k).toList();
    }
    if (p.optional && _rng.nextInt(4) == 0) return const [];
    return [_rng.nextInt(n)];
  }
}
