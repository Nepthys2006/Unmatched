// Every card of every hero, played for real: attack and defense values, BOOST values, schemes,
// and where each card ends up afterwards (nothing lost, nothing left in play by mistake).
// Prompts the cards raise are answered by the AI.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/combat.dart';
import 'package:unmatched_game/engine/defs.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

/// Where a card can be after it was played: anywhere but the hand it came from mid-air.
String whereIs(Game g, Card c) {
  final p = c.owner;
  if (p.discard.contains(c)) return 'discard';
  if (p.inPlay.contains(c)) return 'in play';
  if (p.script.aside.contains(c)) return 'aside';
  if (p.removed.contains(c)) return 'removed';
  if (g.players.any((h) => h.hand.contains(c))) return 'hand';
  if (p.deck.contains(c)) return 'deck';
  if (g.players.any((h) => h.script.stored.contains(c))) return 'stored';
  if (g.playedCards.contains(c)) return 'still in play';
  return 'lost';
}

void main() {
  final data = loadData();
  final heroes = data.heroes.keys.where(isImplemented).toList()..sort();
  const opponent = 'medusa';
  final played = {'attack': 0, 'defense': 0, 'scheme': 0};
  final defs = {'attack': 0, 'defense': 0, 'scheme': 0};
  final skipped = <String>[];
  tearDownAll(() {
    // ignore: avoid_print
    print('played: $played of $defs');
    // ignore: avoid_print
    print('skipped: $skipped');
    // Every card must really have been played: nothing skipped.
    expect(skipped, isEmpty, reason: 'cards not played');
    expect(played, defs, reason: 'cards played');
  });

  /// A scenario with [heroId]'s fighters on the line board and Medusa next to [user].
  (Scenario, Fighter) setup(String heroId, CardDef def, {bool asDefender = false}) {
    final s = asDefender ? Scenario(opponent, heroId) : Scenario(heroId, opponent);
    final me = asDefender ? s.p2 : s.p1, them = asDefender ? s.p1 : s.p2;
    for (final a in [s.a1, s.a2]) {
      a.fallback = AiAgent(level: AiLevel.hard, seed: 3);
    }
    // Jekyll & Hyde: play each card in the form that may use it.
    if (heroId == 'jekyll-hyde') (me.script as dynamic).hyde = def.usedBy.toUpperCase().contains('HYDE');
    bool canUse(Fighter f) => s0(f, def);
    final user = me.fighters.firstWhere(canUse, orElse: () => me.heroFighter);
    s.place(user, 4);
    // The rest of the team further back, so "your fighters" effects have someone to act on.
    var spot = 0;
    for (final f in me.fighters.where((f) => f != user && (f.isHero || !me.script.startsInReserve(f)))) {
      if (spot > 2) break;
      s.place(f, spot++);
    }
    s.place(them.heroFighter, 5);
    prepare(s, me, user, def);
    them.heroFighter
      ..maxHp = 99
      ..hp = 99;
    for (final f in me.fighters) {
      f
        ..maxHp = 99
        ..hp = 99;
    }
    return (s, user);
  }

  for (final id in heroes) {
    group(id, () {
      final hero = data.hero(id);
      for (final def in hero.cards) {
        test('${def.title}: values, BOOST, where it ends up', () async {
          // BOOST: printed value (no modifiers in play), or a die roll.
          final probe = Scenario(id, opponent);
          final card = probe.make(probe.p1, def.title);
          expect(card.def.canBoost, def.boost != null || def.dieBoost, reason: 'can boost');
          if (def.boost != null) expect(probe.game.boostValueOf(card), def.boost, reason: 'BOOST value');

          if (def.isScheme) defs['scheme'] = defs['scheme']! + 1;
          if (def.canAttack) defs['attack'] = defs['attack']! + 1;
          if (def.canDefend) defs['defense'] = defs['defense']! + 1;
          if (def.isScheme) {
            final (s, user) = setup(id, def);
            final c = s.give(user.owner, def.title);
            if (s.game.schemeFighters(user.owner, c).isEmpty) {
              skipped.add('$id/${def.title} (scheme)');
              return;
            }
            final before = s.events.length;
            await s.game.playScheme(user.owner, c);
            played['scheme'] = played['scheme']! + 1;
            expect(s.events.length, greaterThan(before));
            expect(whereIs(s.game, c), isNot(anyOf('lost', 'still in play')), reason: 'scheme after play');
            return;
          }

          if (def.canAttack) {
            final (s, user) = setup(id, def);
            if (s.game.canAttackWith(s.make(user.owner, def.title), user)) {
              final atk = s.give(user.owner, def.title);
              s.a1.queue.insert(0, card_(def.title));
              final target = s.p2.heroFighter;
              s.p2.hand.clear();
              final reach = s.game.inReach(user, target);
              if (reach && s.game.canTargetWith(atk, user, target)) {
                final c = await s.game.resolveCombat(user, target);
                played['attack'] = played['attack']! + 1;
                if (c.attacker.card == atk) checkSide(c.attacker, def);
                expect(whereIs(s.game, atk), isNot(anyOf('lost', 'still in play')), reason: 'attack card after combat');
              } else {
                skipped.add('$id/${def.title} (attack: target)');
              }
            } else {
              skipped.add('$id/${def.title} (attack: cannot attack with it)');
            }
          }

          if (def.canDefend) {
            final (s, user) = setup(id, def, asDefender: true);
            if (s.game.canDefendWith(s.make(user.owner, def.title), user)) {
              final dc = s.give(user.owner, def.title);
              final attacker = s.p1.heroFighter;
              final atk = s.give(s.p1, 'Snipe'); // 3, AFTER COMBAT: draw 1
              s.a1.queue.insert(0, card_('Snipe'));
              s.a2.queue.insert(0, card_(def.title));
              final c = await s.game.resolveCombat(attacker, user);
              // Played: it was revealed as the defense (some cards then swap themselves out).
              final wasPlayed = s.game.turn.played.contains(dc);
              if (wasPlayed) played['defense'] = played['defense']! + 1;
              if (!wasPlayed) skipped.add('$id/${def.title} (defense: not played)');
              if (c.defender.card == dc) {
                checkSide(c.defender, def);
                // The attack hits for its value minus the defense (when nothing changes them).
                expect(c.attackerWon, c.combatDamage > 0);
              }
              expect(whereIs(s.game, dc), isNot(anyOf('lost', 'still in play')), reason: 'defense card after combat');
              expect(whereIs(s.game, atk), isNot(anyOf('lost', 'still in play')), reason: "the attacker's card");
            } else {
              skipped.add('$id/${def.title} (defense: cannot defend with it)');
            }
          }
        });
      }
    });
  }
}

CardAnswer card_(String t) => card(t);

/// Puts in place what a card needs before it can be played (Black Widow's missions).
void prepare(Scenario s, Player me, Fighter user, CardDef def) {
  final g = s.game;
  final foe = g.players.firstWhere((p) => p != me);
  switch (def.upperTitle) {
    case 'THE KINSHASA DIRECTIVE': // Black Widow in her own start space
      s.place(user, me.startSpace);
    case 'THE MADRIPOOR SANCTION': // Black Widow in an opponent's start space
      foe.heroFighter.space = 5;
      s.place(user, foe.startSpace);
    case 'THE MOSCOW PROTOCOL': // an opposing fighter was damaged this turn
      g.turn.damaged.add(foe.heroFighter);
  }
}

/// The fighter that may play [def] (its "used by").
bool s0(Fighter f, CardDef def) => f.owner.script.fighterMayUse(Card(0, def, 0, f.owner), f);

/// The value breakdown starts from the printed value.
void checkSide(Side side, CardDef def) {
  final g = side.combat;
  expect(side.card!.title, def.title);
  final lines = side.player.script.game.valueOf(side).lines;
  expect(lines.first.$2, side.printed, reason: 'breakdown starts at the printed value');
  expect(g.resolved, isTrue);
}
