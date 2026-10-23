/// The Witcher – Steel & Silver: Ancient Leshen, Geralt of Rivia, Ciri.
library;

import '../combat.dart';
import '../defs.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

/// "Discard this card at the end of your turn if you didn't attack."
bool _noAttack(Game g, Ongoing m) => g.turn.attacks == 0;

// =========================================================================== Ancient Leshen

/// Heart of the Forest: +3 to the Leshen's attacks if it already attacked this turn. Wolves have
/// a move value of 3.
class AncientLeshen extends HeroScript {
  bool vanished = false;
  Fighter get leshen => me.heroFighter;
  Iterable<Fighter> get wolves => me.fighters.where((f) => f.isSidekick);

  @override
  int moveValue(Game g, Fighter f, int v) => f.owner == me && f.isSidekick ? 3 : v;

  @override
  Iterable<ValueOp> valueOps(Game g, Side s) sync* {
    if (s.player == me && s.isAttacker && s.fighter == leshen && (game.turn.attacksBy[leshen] ?? 0) > 1) {
      yield const ValueOp.add(3, 'Heart of the Forest');
    }
  }

  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active != me || !vanished) return;
    vanished = false;
    leshen.offBoard = false;
    final from = leshen.space;
    final s = await g.chooseSpace(me, g.board.spaceIds.where(g.isEmpty), 'Place the Leshen in any space',
        intent: Intent.moveOwn, subject: leshen);
    leshen.space = s ?? from;
    await g.emit(Returned(leshen));
    await g.draw(me, 1);
  }

  Future<void> summonWolf(Fx x) async {
    if (leshen.onBoard) {
      await x.game.summon(me, wolves.first.id, x.zoneSpaces(leshen), moveIfNone: true, text: "Summon a Wolf in the Leshen's zone");
    }
  }

  @override
  List<String> status() => [if (vanished) 'VANISHED'];

  @override
  Map<String, CardScript> get cards => {
        'DISTURBING HOWLS': CardScript(after: (x) async {
          await pushOpponent(x, 2);
          x.gainActions(1);
        }),
        'FLOCK OF BIRDS': CardScript(after: (x) async {
          if (leshen.onBoard) await x.place(leshen, x.allSpaces, text: 'You may place the Leshen in any space', optional: true);
        }),
        'HARRYING STRIKE': CardScript(during: (x) async {
          final n = friendsAdjacentTo(x, x.oppFighter);
          if (n > 0) x.addValue(2 * n, 'Your fighters adjacent ($n)');
        }),
        'NATURE ABOUNDS': CardScript(after: (x) => x.draw(friendsAdjacentTo(x, x.oppFighter))),
        'PLANTED FEET': CardScript(after: (x) async {
          if (!x.game.turn.leftSpace.contains(x.fighter)) await x.draw(1);
        }),
        'PRIMEVAL GUARDIAN': CardScript(
          during: (x) async {
            final c = await x.game.discardTopOfDeck(x.opp);
            if (c != null && x.oppCard != null) x.game.addOp(x.oppSide, ValueOp.add(c.def.boost ?? 0, '${c.title} (BOOST)'));
          },
          after: (x) => moveEach(x, wolves, 3),
        ),
        'PRIMEVAL SLAM': CardScript(after: (x) async {
          await summonWolf(x);
          await moveEach(x, wolves, 3);
        }),
        'STRENGTH OF THE PACK': CardScript(
          effect: summonWolf,
          ongoing: (g, card, f) => Ongoing(
            card,
            onStartOfTurn: (g, m) async {
              await g.heal(leshen, 1);
            },
            discardIf: (g, m) => !leshen.onBoard || !wolves.any((w) => w.onBoard && g.sameZone(w, leshen)),
          ),
        ),
        'VANISH INTO MURDER': CardScript(effect: (x) async {
          for (final f in enemiesInZone(x, leshen).toList()) {
            await x.damage(f, 1);
          }
          vanished = true;
          leshen.offBoard = true;
          await x.game.emit(StatusChanged(me, 'The Leshen vanishes from the board.'));
        }),
        'COMMAND THE FOREST': oppDiscardsAfter(1, ifWon: true),
      };
}

// ========================================================================== Geralt of Rivia

const _gear = {
  'SWORD': ['SWORD OF STEEL', 'SWORD OF SILVER'],
  'ARMOR': ['WOLF MEDALLION', 'ARMOR OF THE FORGOTTEN WOLF'],
  'POTION': ['BLIZZARD', 'TAWNY OWL'],
};
bool isGear(CardDef c) => c.upperTitle.startsWith('GEAR');
String _gearName(CardDef c) => c.upperTitle.replaceFirst(RegExp(r'^GEAR:\s*'), '');

/// Always Prepared: choose a SWORD, ARMOR and POTION at the start; 2 copies of each go in the deck.
class Geralt extends HeroScript {
  final Set<String> chosen = {};

  @override
  Future<void> beforeDeck() async {
    for (final e in _gear.entries) {
      final i = await game.chooseOption(me, [for (final n in e.value) _title(n)], 'Always Prepared: choose your ${e.key}',
          intent: Intent.none);
      chosen.add(e.value[i]);
    }
    await game.say('Geralt prepares: ${chosen.map(_title).join(', ')}.');
  }

  String _title(String n) => n.split(' ').map((w) => w.length <= 2 ? w.toLowerCase() : w[0] + w.substring(1).toLowerCase()).join(' ');

  @override
  Iterable<CardDef> deckCards() => super.deckCards().where((c) => !isGear(c) || chosen.contains(_gearName(c)));

  Fighter get geralt => me.heroFighter;

  @override
  Map<String, CardScript> get cards => {
        'WITCHER SENSES': CardScript(effect: (x) async {
          final options = [...x.me.deck, ...x.me.discard].where((c) => isGear(c.def)).toList();
          final c = await x.game.chooseCard(x.me, options, 'Witcher Senses: take a GEAR card', intent: Intent.gainOwn);
          if (c == null) return;
          final fromDeck = x.me.deck.contains(c);
          await x.game.toHand(c, reason: ' (Witcher Senses)');
          if (fromDeck) await x.game.toDeck(x.card!, shuffle: true);
        }),
        'DISCIPLINED DUELIST': CardScript(after: (x) async {
          switch (x.oppCard?.def.value) {
            case 2:
              if (await x.yesNo('Disciplined Duelist: draw 1 card?')) await x.draw(1);
            case 3:
              await x.damage(x.oppFighter, 1);
            case 4:
              await x.discard(x.opp, 1);
          }
        }),
        'GEAR: ARMOR OF THE FORGOTTEN WOLF': CardScript(
          during: (x) async {
            final n = x.adjacentTo(geralt).length;
            if (n > 0) x.addValue(n, 'Fighters adjacent to Geralt');
          },
          after: (x) async => x.game.endTurn(),
        ),
        'GEAR: BLIZZARD': CardScript(
          effect: (x) async {
            await x.draw(1);
            await x.move(geralt, 3);
          },
          ongoing: (g, card, f) => Ongoing(card, blocksActions: true, discardIf: _noAttack),
        ),
        'GEAR: SWORD OF SILVER': CardScript(immediately: (x) async {
          if ((x.oppCard?.def.value ?? 0) >= 4) x.ignoreOpponentValue();
        }),
        'GEAR: TAWNY OWL': CardScript(
          effect: (x) async {
            await x.draw(2);
            x.gainActions(1);
          },
          ongoing: (g, card, f) => Ongoing(card, ignoreDiscards: true, discardIf: _noAttack),
        ),
        'IGNI': CardScript(after: (x) async {
          final opp = x.oppFighter;
          await x.damage(opp, 2);
          for (final f in x.adjacentTo(geralt).where((f) => f != opp).toList()) {
            await x.damage(f, 1);
          }
        }),
        'PLOT TWIST': CardScript(after: (x) async {
          await pickDiscard(x);
          await x.draw(1);
        }),
        'RIPOSTE': CardScript(after: (x) async {
          final adj = x.adjacentTo(geralt).toList();
          if (adj.isEmpty) return;
          final i = await x.option(['Deal 1 damage to an adjacent fighter', 'Geralt swaps spaces with an adjacent fighter'], 'Riposte: choose one');
          final f = await x.chooseFighter(adj, i == 0 ? 'Deal 1 damage to' : 'Swap with', intent: i == 0 ? Intent.harm : Intent.none);
          if (f == null) return;
          if (i == 0) {
            await x.damage(f, 1);
          } else {
            await x.game.swap(geralt, f);
          }
        }),
        'YRDEN': CardScript(
          immediately: (x) async {
            final t = x.oppFighter;
            x.game.addTurnMod(TurnMod(name: 'Yrden', cannotLeaveFn: (g, f) => f == t));
          },
          after: (x) => x.move(geralt, 2),
        ),
        'ANNOYING TUNE': CardScript(after: (x) => pushOpponent(x, 4)),
        'GEAR: SWORD OF STEEL': CardScript(after: (x) async => x.gainActions(x.oppFighter.alive && x.oppFighter.hp >= 8 ? 2 : 1)),
        'REND': boostable,
        "DAMN, YOU'RE UGLY": vanilla,
        'GEAR: WOLF MEDALLION': CardScript(
          immediately: (x) async => x.cancelOpponent(),
          during: (x) async {
            if (!x.adjacent(x.oppFighter, geralt)) x.ignoreOpponentValue();
          },
        ),
      };
}

// ===================================================================================== Ciri

const _source = {'LION CUB OF CINTRA', 'PUSHED TO THE BRINK', 'THE LADY OF SPACE AND TIME', 'ZIREAEL', 'CHILD OF THE ELDER BLOOD'};
bool isSource(Card c) => _source.contains(c.def.upperTitle);

/// Source cards resolve the highest threshold met by the number of Source cards in Ciri's discard
/// pile. With 7 or more, effects on Ciri's cards cannot be canceled.
class Ciri extends HeroScript {
  int get source => me.discard.where(isSource).length;
  Fighter get ciri => me.heroFighter;

  @override
  bool uncancelable(Game g, Side s) => s.player == me && source >= 7;

  @override
  List<String> status() => ['SOURCE $source'];

  /// Runs the effect for the highest threshold met (no choosing a lower one).
  Future<void> tier(Fx x, Map<int, Effect> tiers) async {
    final n = source;
    final reached = tiers.keys.where((k) => k <= n).toList()..sort();
    if (reached.isEmpty) return;
    await x.game.say('Source $n: resolving the ${reached.last} effect.');
    await tiers[reached.last]!(x);
  }

  @override
  Map<String, CardScript> get cards => {
        'PUSHED TO THE BRINK': CardScript(after: (x) => tier(x, {
              2: (x) => x.damage(x.oppFighter, 1),
              7: (x) async {
                final targets = x.enemies.where((f) => ciri.onBoard && x.board.distance(ciri.space!, f.space!) <= 3);
                final f = await x.chooseFighter(targets, 'Deal 2 damage to an opposing fighter within 3 spaces of Ciri', intent: Intent.harm);
                if (f != null) await x.damage(f, 2);
              },
            })),
        'ZIREAEL': CardScript(during: (x) => tier(x, {
              3: (x) async => x.setValue(4),
              5: (x) async {
                x.setValue(4);
                await x.discard(x.opp, 1, random: true);
              },
            })),
        'CHILD OF THE ELDER BLOOD': CardScript(effect: (x) => tier(x, {
              4: (x) async {
                for (final f in x.inZoneOf(ciri).where((f) => f != ciri).toList()) {
                  await x.damage(f, 1);
                }
              },
              9: (x) async {
                for (final f in x.inZoneOf(ciri).where((f) => f != ciri).toList()) {
                  await x.damage(f, 3);
                }
              },
            })),
        'LION CUB OF CINTRA': CardScript(during: (x) => tier(x, {1: (x) async => x.setValue(4), 5: (x) async => x.setValue(7)})),
        'BANE OF THE AEN ELLE': CardScript(after: (x) async {
          final path = await x.move(x.fighter, 4, throughOpp: true);
          final f = await x.chooseFighter(x.game.movedThrough(path, x.me), 'Deal 1 damage to a fighter he moved through', intent: Intent.harm);
          if (f != null) await x.damage(f, 1);
        }),
        'BLINK': CardScript(after: (x) => x.move(ciri, 3, throughOpp: true)),
        'CHANNEL THE SOURCE': CardScript(during: (x) async {
          final src = x.me.hand.where(isSource);
          final cards = await x.game.chooseCards(x.me, src, 0, src.length, 'Channel the Source: discard Source cards (+2 each)',
              intent: Intent.boost);
          for (final c in cards) {
            await x.game.discardCard(c, reason: ' (Channel the Source)');
          }
          if (cards.isNotEmpty) x.addValue(2 * cards.length, 'Source cards discarded (${cards.length})');
        }),
        'SEARCHING STRIKE': CardScript(after: (x) async {
          if (!x.won) return;
          final c = await x.game.chooseCard(x.me, x.me.deck.where(isSource), 'Search your deck for a Source card',
              optional: true, skipLabel: "Don't search", intent: Intent.gainOwn);
          if (c == null) return;
          await x.game.emit(Revealed(x.me, [c], ' (Searching Strike)'));
          await x.game.toHand(c);
          await x.game.shuffleDeck(x.me);
        }),
        'THE LADY OF SPACE AND TIME': CardScript(after: (x) => tier(x, {
              3: (x) async {
                final c = await x.game.chooseCard(x.me, x.me.discard, 'Return a card from your discard pile to the top of your deck',
                    intent: Intent.gainOwn);
                if (c != null) await x.game.toDeck(c);
              },
              8: (x) async {
                final c = await x.game.chooseCard(x.me, x.me.discard, 'Return a card from your discard pile to your hand', intent: Intent.gainOwn);
                if (c != null) await x.game.toHand(c);
                await x.draw(1);
              },
            })),
        'UNICORN ALLY': CardScript(
          effect: (x) => x.heal(ciri, 2),
          ongoing: (g, card, f) => Ongoing(
            card,
            onAfterCombat: (g, m, c) async {
              if (c.attacker.player == m.owner || c.defender.player == m.owner) await g.draw(m.owner, 1);
            },
            discardIf: (g, m) => m.owner.hand.length >= 5,
          ),
        ),
      };
}
