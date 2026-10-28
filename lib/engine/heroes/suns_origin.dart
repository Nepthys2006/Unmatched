/// Sun's Origin: Oda Nobunaga and Tomoe Gozen.
library;

import '../combat.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// ============================================================================ Oda Nobunaga

/// Master Strategist: other friendly fighters in Oda Nobunaga's zone add +1 to the value of their
/// played combat cards (not Oda himself).
/// Flanked: an opposing fighter adjacent to two or more fighters under your control (your own
/// fighters only, not teammates').
class OdaNobunaga extends HeroScript {
  Fighter get oda => me.heroFighter;

  bool flanked(Fighter o) => o.onBoard && me.onBoard.where((f) => game.adjacent(f, o)).length >= 2;

  @override
  List<String> reference() => const ['Flanked: an opposing fighter adjacent to two or more of your fighters.'];

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    final f = s.fighter;
    if (s.card == null || f == oda || !f.isFriendOf(me) || !oda.onBoard || !g.sameZone(f, oda)) return;
    yield const ValueOp.add(1, 'Master Strategist');
  }

  @override
  Map<String, CardScript> get cards => {
        'FIRE AND FLAMES': valueIf((x) => flanked(x.oppFighter), 5),
        'PRAGMATISM': cancelCard,
        'REINFORCE': CardScript(effect: (x) async {
          for (final i in await chooseDifferent(x, ['Each friendly fighter recovers 1 health', 'Draw 2 cards', 'Gain 1 action'], 2,
              'Reinforce: choose two different effects')) {
            switch (i) {
              case 0:
                for (final f in x.myFighters.toList()) {
                  await x.heal(f, 1);
                }
              case 1:
                await x.draw(2);
              default:
                x.gainActions(1);
            }
          }
        }),
        'STUDENT OF WAR': CardScript(after: (x) async {
          if (x.attacking && x.damageDealt > 0) await x.draw(x.damageDealt);
        }),
        'BATTLE MANEUVERS': CardScript(after: (x) async {
          await x.draw(1);
          await moveEach(x, x.myFighters, 2);
        }),
        'DEMON KING OF THE SIXTH HEAVEN': CardScript(effect: (x) async {
          for (final f in x.enemies.where(flanked).toList()) {
            await x.damage(f, 2);
          }
        }),
        'LIGHTNING AND THUNDER': CardScript(
          immediately: (x) async {
            if (flanked(x.oppFighter)) x.cancelOpponent();
          },
          after: (x) => x.move(x.fighter, 2),
        ),
        'PATIENCE AND STRATEGY': CardScript(after: (x) async {
          if (flanked(x.oppFighter) && x.fighter.alive) await x.heal(x.fighter, 2);
        }),
        'SPRING THE TRAP': CardScript(
          immediately: (x) async {
            final self = x.fighter;
            final friends = x.adjacentTo(self).where((f) => f.owner == x.me).toList();
            final f = await x.chooseFighter(friends, 'Spring the Trap: swap with an adjacent friendly fighter? It becomes the defender',
                optional: true, intent: Intent.none);
            if (f != null && await x.game.swap(self, f)) x.mySide.fighter = f;
          },
          after: (x) async {
            if (x.oppFighter.alive) await x.damage(x.oppFighter, 1);
          },
        ),
        'SUN AND MOON': CardScript(during: (x) async {
          if (flanked(x.oppFighter)) x.ignoreOpponentValue();
        }),
      };
}

// ============================================================================= Tomoe Gozen

/// Attack of Opportunity: when an opposing hero leaves Tomoe Gozen's zone (however it happens,
/// even several times in one move), deal 1 damage to that hero. Not when she is the one moving.
class TomoeGozen extends HeroScript {
  Fighter get tomoe => me.heroFighter;

  @override
  Future<void> relocated(Game g, Fighter f, List<int> path) async {
    if (!f.isHero || !f.isEnemyOf(me) || !tomoe.onBoard || f == tomoe) return;
    final here = tomoe.space!;
    bool inZone(int s) => g.board.sharesZone(here, s);
    for (var i = 0; i + 1 < path.length; i++) {
      if (!inZone(path[i]) || inZone(path[i + 1]) || !f.alive) continue;
      await g.say('Attack of Opportunity: ${f.name} leaves Tomoe Gozen\'s zone.');
      await g.damage(f, 1, info: DamageInfo(source: tomoe, by: me));
    }
  }

  /// Lord Kiso's Final Stand: up to [n] spaces, through sidekicks (and friends, as always).
  Map<int, List<int>> throughSidekicks(int n) {
    final g = game, f = tomoe;
    bool blocked(int s) => g.fightersAt(s).any((o) => o != f && o.isEnemyOf(me) && !o.isSidekick && !o.isSmall);
    final paths = <int, List<int>>{f.space!: [f.space!]};
    var frontier = [f.space!];
    for (var d = 0; d < n && frontier.isNotEmpty; d++) {
      final next = <int>[];
      for (final s in frontier) {
        for (final nb in g.board.neighbours(s)) {
          if (paths.containsKey(nb) || blocked(nb)) continue;
          paths[nb] = [...paths[s]!, nb];
          next.add(nb);
        }
      }
      frontier = next;
    }
    return {
      for (final e in paths.entries)
        if (e.key == f.space || g.canOccupy(f, e.key)) e.key: e.value
    };
  }

  @override
  Map<String, CardScript> get cards => {
        'DEEDS OF VALOR': CardScript(during: (x) async {
          final combat = x.combat;
          x.game.addTurnMod(TurnMod(
            name: 'Deeds of Valor',
            modifyDamageFn: (g, target, n, info) => target == tomoe && info.combat && g.combat == combat && n > 2 ? 2 : n,
          ));
        }),
        'A WORTHY OPPONENT': valueIf((x) => x.oppFighter.isHero, 5),
        'FEARSOME STRENGTH': CardScript(
          immediately: (x) async {
            final f = await x.chooseFighter(x.adjacentTo(tomoe).toList(), 'Fearsome Strength: swap spaces with an adjacent fighter?',
                optional: true, intent: Intent.none);
            if (f != null) await x.game.swap(tomoe, f);
          },
          after: (x) async {
            final f = await x.chooseFighter(x.adjacentTo(tomoe).toList(), 'Fearsome Strength: deal 1 damage to an adjacent fighter',
                intent: Intent.harm);
            if (f != null) await x.damage(f, 1);
          },
        ),
        'FIVE AGAINST THOUSANDS': CardScript(after: (x) async {
          if (!x.adjacent(tomoe, x.oppFighter) || x.me.hand.isEmpty || !x.game.isInPlay(x.card!)) return;
          final c = await x.game.chooseCard(x.me, x.me.hand, 'Five Against Thousands: discard a card to put this card back into your hand?',
              optional: true, skipLabel: 'No', intent: Intent.loseOwn, source: x.card);
          if (c == null) return;
          await x.game.discardCard(c);
          await x.game.returnPlayedToHand(x.card!);
        }),
        "LORD KISO'S FINAL STAND": CardScript(effect: (x) async {
          if (tomoe.onBoard) {
            await x.game.moveFighter(tomoe, 3, chooser: x.me, source: x.card, routes: throughSidekicks(3),
                text: "Lord Kiso's Final Stand: move Tomoe Gozen up to 3 (through sidekicks)");
          }
          final i = await x.option(['Tomoe Gozen recovers 2 health', 'Gain 1 action'], "Lord Kiso's Final Stand: choose one");
          if (i == 0) {
            await x.heal(tomoe, 2);
          } else {
            x.gainActions(1);
          }
        }),
        'REFUSE TO RETREAT': CardScript(
          immediately: (x) async =>
              x.game.addTurnMod(TurnMod(name: 'Refuse to Retreat', cannotLeaveFn: (g, f) => f == tomoe)),
          after: (x) async {
            if (x.adjacent(tomoe, x.oppFighter)) await x.discard(x.opp, 1);
          },
        ),
        'WITNESS MY LAST BATTLE': CardScript(
          onlyTarget: (g, a, t) => g.adjacent(a, t),
          onReveal: (x) async => x.mySide.faceUp = true,
          after: (x) async => x.game.endTurn(),
        ),
        "A WARRIOR'S WAY": CardScript(after: (x) async {
          final o = x.oppFighter;
          await pushOpponent(x, 3);
          if (!o.isHero || !o.onBoard || !tomoe.onBoard) return;
          await x.place(tomoe, x.board.neighbours(o.space!), text: "A Warrior's Way: place Tomoe Gozen next to ${o.name}");
        }),
        'CONFRONT ANY DEMON OR GOD': CardScript(after: (x) async {
          await x.draw(1);
          if (x.lost) await pickDiscard(x);
        }),
        'FLASH OF STEEL': CardScript(
          immediately: (x) async {
            if (x.oppFighter.isHero) x.cancelOpponent();
          },
          after: (x) async {
            if (x.adjacent(x.fighter, x.oppFighter)) await x.damage(x.oppFighter, 1);
          },
        ),
        'PIERCING SHOT': drawAfter(2),
      };
}
