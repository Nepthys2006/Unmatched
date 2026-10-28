/// Marvel – Brains and Brawn (Doctor Strange), For King and Country (Black Widow), and
/// Buffy the Vampire Slayer (Willow).
library;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// =========================================================================== Doctor Strange

/// Dark Pact: after each combat, if Doctor Strange played a card, you may deal 1 damage to him.
/// If you do, put that card on the bottom of your deck and draw 1 card.
class DoctorStrange extends HeroScript {
  Fighter get strange => me.heroFighter;
  Fighter? get wong => me.fighters.where((f) => f.isSidekick).firstOrNull;

  @override
  Future<void> afterCombat(Game g, Combat c) async {
    if (!c.involves(strange)) return;
    final card = c.sideOfFighter(strange).card;
    if (card == null || card.virtual || !g.isInPlay(card) || !strange.alive || strange.hp <= 1) return;
    if (!await g.yesNo(me, 'Dark Pact: take 1 damage to put ${card.title} on the bottom of your deck and draw 1?')) return;
    await g.damage(strange, 1, info: DamageInfo(by: me));
    await g.toDeck(card, bottom: true);
    await g.draw(me, 1);
  }

  @override
  Map<String, CardScript> get cards => {
        'THE MISTS OF MUNNOPOR': CardScript(immediately: (x) async {
          final s = x.oppSide;
          if (s.card == null || !s.isAttacker || s.card!.virtual) return;
          final g = x.game;
          final attacker = s.fighter;
          await g.replaceCard(s, null, oldTo: Zone.discard);
          // Rearrange the deck in one go so every card is always in a zone.
          final deck = x.opp.deck;
          final i = deck.indexWhere((c) => g.canAttackWith(c, attacker));
          final revealed = deck.sublist(0, i < 0 ? deck.length : i);
          final found = i < 0 ? null : deck[i];
          deck.removeRange(0, i < 0 ? deck.length : i + 1);
          deck.addAll(List.of(revealed)..shuffle(g.rng));
          if (found != null) x.opp.hand.add(found);
          if (revealed.isNotEmpty) await g.emit(Revealed(x.opp, revealed, ' (The Mists of Munnopor)'));
          if (found != null) await g.replaceCard(s, found);
        }),
        'SEVEN SUNS OF CINNIBUS': CardScript(during: (x) async {
          for (var i = 0; i < 2; i++) {
            if (!await x.boostThis(blind: true, text: 'Seven Suns: BLIND BOOST (${i + 1} of 2)?')) break;
          }
          if (x.game.valueOf(x.mySide).total > 7) x.game.ignoreValue(x.mySide);
        }),
        'EYE OF AGAMOTTO': CardScript(effect: (x) async {
          for (final c in x.me.hand.toList()) {
            await x.game.toDeck(c, shuffle: true);
          }
          await x.draw(5);
          x.gainActions(1);
        }),
        'STEADFAST DISCIPLE': CardScript(after: (x) async {
          final w = wong;
          if (w != null && x.adjacent(w, x.oppFighter)) {
            await x.damage(x.oppFighter, 1);
            await x.draw(1);
          }
        }),
        'THE WINDS OF WATOOMB': CardScript(after: (x) async {
          final g = x.game;
          final starts = g.board.startSpaces.toList();
          if (strange.onBoard) {
            await g.placeFighter(strange, starts, chooser: x.opp, text: 'Place Doctor Strange in a starting space');
          }
          final o = x.oppFighter;
          if (o.onBoard) await g.placeFighter(o, starts.where((s) => s != strange.space), chooser: x.me, text: 'Place the opposing fighter in another starting space');
          await g.shuffleDeck(x.me);
          await g.shuffleDeck(x.opp);
        }),
        'BOLTS OF BALTHAKK': CardScript(
          during: (x) async => x.boostThis(blind: true, text: 'Bolts of Balthakk: BLIND BOOST?'),
          after: (x) async {
            if (x.won) x.gainActions(1);
          },
        ),
        'CLOAK OF LEVITATION': CardScript(during: (x) async {
          if (x.adjacent(strange, x.oppFighter)) x.ignoreOpponentValue();
        }),
        'MASTER OF KAMAR-TAJ': valueIf((x) => wong != null && x.adjacent(strange, wong!), 4),
        "NO REALLY, I'M A DOCTOR": CardScript(effect: (x) async {
          final c = await x.game.chooseCard(x.me, x.me.hand, 'Reveal a card and put it on top of your deck', intent: Intent.loseOwn);
          if (c == null) return;
          await x.game.emit(Revealed(x.me, [c], ''));
          await x.game.toDeck(c);
          final f = await x.chooseFighter([strange, ...x.adjacentTo(strange).where((f) => f.isFriendOf(x.me))], 'Who recovers ${c.def.boost ?? 0} health?',
              intent: Intent.help);
          if (f != null) await x.heal(f, c.def.boost ?? 0);
        }),
        'THE RINGS OF RAGGADORR': CardScript(after: (x) async {
          if (!x.won || x.damageDealt <= 0) return;
          final f = x.fighter;
          for (final t in [f, ...x.adjacentTo(f).where((o) => o.isFriendOf(x.me))]) {
            await x.heal(t, x.damageDealt);
          }
        }),
      };
}

// ============================================================================== Black Widow

bool _isMission(Card c) => const {
      'THE BUDAPEST GAMBIT',
      'THE FIRENZE AGENDA',
      'THE KINSHASA DIRECTIVE',
      'THE MADRIPOOR SANCTION',
      'THE MOSCOW PROTOCOL'
    }.contains(c.def.upperTitle);

/// Mission Ready: THE MOSCOW PROTOCOL starts in your hand (a 6-card starting hand). Missions are
/// schemes that can only be played when their requirement is met.
class BlackWidow extends HeroScript {
  Fighter get widow => me.heroFighter;

  @override
  Future<void> beforeStartingHand() async {
    final moscow = me.deck.where((c) => c.def.upperTitle == 'THE MOSCOW PROTOCOL').firstOrNull;
    if (moscow != null) {
      me.deck.remove(moscow);
      me.hand.add(moscow);
    }
  }

  /// "Acquire a new mission": reveal cards from the top of your deck until a mission, take it,
  /// shuffle the rest back.
  Future<void> acquireMission(Fx x) async {
    final i = x.me.deck.indexWhere(_isMission);
    if (i >= 0) {
      final c = x.me.deck.removeAt(i);
      x.me.hand.add(c);
      await x.game.emit(CardMoved(c, Zone.deck, Zone.hand, reason: ' (new mission)'));
    }
    if (i != 0 && x.me.deck.isNotEmpty) await x.game.shuffleDeck(x.me);
  }

  CardScript mission(bool Function(Game g, Player p, Fighter f) req, Effect effect) =>
      CardScript(canPlay: req, effect: (x) async {
        await effect(x);
        await acquireMission(x);
      });

  bool _inStart(Game g, int start) => widow.onBoard && widow.space == start;

  @override
  Map<String, CardScript> get cards => {
        'THE BUDAPEST GAMBIT': mission((g, p, f) => p.hand.length - 1 <= 2, (x) async {
          await x.draw(5);
          for (final o in x.opponents.toList()) {
            await x.discard(o, 1, random: true);
          }
        }),
        'THE FIRENZE AGENDA': mission((g, p, f) => g.adjacentFighters(widow).any((o) => o.isEnemyOf(me) && o.isHero), (x) async {
          for (final f in enemiesInZone(x, widow).toList()) {
            await x.damage(f, 2);
          }
        }),
        'THE KINSHASA DIRECTIVE': mission((g, p, f) => _inStart(g, me.startSpace), (x) => x.discard(x.opp, 2)),
        'THE MADRIPOOR SANCTION': mission((g, p, f) => g.enemiesOf(me).any((o) => _inStart(g, o.startSpace)), (x) async {
          // (she may have been moved off it since the mission was checked)
          final o = x.opponents.where((o) => widow.onBoard && o.startSpace == widow.space).firstOrNull;
          if (o == null) return;
          for (final f in o.onBoard.toList()) {
            await x.damage(f, 2);
          }
        }),
        'THE MOSCOW PROTOCOL': mission((g, p, f) => g.turn.damaged.any((o) => o.isEnemyOf(me)), (x) async {
          await x.draw(1);
          x.gainActions(1);
        }),
        "WIDOW'S LINE": CardScript(after: (x) => pushOpponent(x, 2)),
        'ACTING DIRECTOR OF S.H.I.E.L.D.': CardScript(after: (x) async {
          await moveEach(x, x.myFighters, 3, through: true);
          final c = await x.game.chooseCard(x.me, x.me.discard.where((c) => c.def.isScheme), 'Shuffle a scheme from your discard pile into your deck',
              intent: Intent.gainOwn);
          if (c != null) await x.game.toDeck(c, shuffle: true);
        }),
        "WIDOW'S STING": CardScript(after: (x) => x.move(widow, 3)),
        'CAUGHT IN A WEB': CardScript(during: (x) async => x.cancelOpponentAfter()),
        'LIFE MODEL DECOY': CardScript(after: (x) async {
          final m = x.fighter;
          if (!m.defeated || !widow.onBoard) return;
          final s = await x.chooseSpace(x.board.neighbours(widow.space!).where(x.game.isEmpty), 'Place Maria Hill next to Black Widow',
              intent: Intent.moveOwn, subject: m);
          if (s != null) await x.game.revive(m, s, hp: 3);
        }),
        "WIDOW'S BITE": oppDiscardsAfter(1, ifWon: true),
        'DOUBLE IDENTITY': CardScript(immediately: (x) async {
          final maria = x.me.fighters.where((f) => f.isSidekick).firstOrNull;
          if (maria == null || !maria.onBoard || !widow.onBoard) return;
          final other = x.fighter == widow ? maria : widow;
          if (await x.yesNo('Swap Black Widow and Maria Hill? ${other.name} becomes the defender.', intent: Intent.none) &&
              await x.game.swap(widow, maria)) {
            x.mySide.fighter = other;
          }
        }),
        'FAKE OUT': CardScript(after: (x) async {
          if (x.lost) {
            await x.draw(1);
            x.gainActions(1);
          }
        }),
        "WIDOW'S KISS": CardScript(immediately: (x) async {
          final t = x.oppFighter;
          x.game.addTurnMod(TurnMod(name: "Widow's Kiss", cannotLeaveFn: (g, f) => f == t));
        }),
      };
}

// =================================================================================== Willow

/// When Willow or Tara is dealt damage, Willow becomes Dark Willow. At the end of your turn, if
/// Dark Willow is adjacent to Tara, she becomes Willow. (DARK) effects need Dark Willow.
class Willow extends HeroScript {
  bool dark = false;
  Fighter get willow => me.heroFighter;
  Fighter? get tara => me.fighters.where((f) => f.isSidekick).firstOrNull;

  @override
  String get heroName => dark ? 'Dark Willow' : 'Willow';

  Future<void> setDark(bool v) async {
    if (dark == v) return;
    dark = v;
    await game.emit(StatusChanged(me, v ? 'Willow becomes Dark Willow!' : 'Dark Willow becomes Willow again.'));
  }

  @override
  Future<void> onDamaged(Game g, Fighter f, int amount, DamageInfo info) async {
    if (amount > 0 && (f == willow || f == tara)) await setDark(true);
  }

  @override
  Future<void> endOfTurn(Game g, Player active) async {
    final t = tara;
    if (active == me && dark && t != null && g.adjacent(willow, t)) await setDark(false);
  }

  @override
  List<String> status() => [if (dark) 'DARK'];

  @override
  Map<String, CardScript> get cards => {
        'BLACK MAGIC': CardScript(during: (x) async {
          if (dark) await x.boostThis(blind: true, text: 'Dark Willow: BLIND BOOST');
        }),
        'FLAYED ALIVE': CardScript(during: (x) async {
          if (dark) await x.boostThis(blind: true, text: 'Dark Willow: BLIND BOOST');
        }),
        'HACKER': CardScript(after: (x) async {
          if (x.me.deck.isEmpty) return;
          final top = x.me.deck.first;
          x.me.script.seen([top]);
          final i = await x.option(['Keep ${top.title} on top', 'Put ${top.title} on the bottom'], 'Hacker: the top card of your deck is ${top.title}');
          if (i == 1) {
            x.me.deck
              ..removeAt(0)
              ..add(top);
          }
        }),
        'LOVE AND LOSS': CardScript(effect: (x) async {
          await x.draw(2);
          if (!dark) return;
          await x.game.discardTopOfDeck(x.me);
          await x.game.discardTopOfDeck(x.me);
          final f = await x.chooseFighter(x.inZoneOf(willow).where((f) => f.isSidekick), 'Deal 3 damage to a sidekick in your zone', intent: Intent.harm);
          if (f != null) await x.damage(f, 3);
        }),
        'RESURRECT': CardScript(effect: (x) async {
          final down = x.me.fighters.where((f) => f.defeated && f.isSidekick);
          final f = await x.chooseFighter(down, 'Choose a defeated friendly fighter', intent: Intent.help);
          if (f == null || !willow.onBoard) return;
          final s = await x.chooseSpace(x.zoneSpaces(willow).where(x.game.isEmpty), "Place them in Willow's zone", intent: Intent.moveOwn, subject: f);
          if (s != null) await x.game.revive(f, s, hp: 3);
        }),
        'WHEN GOOD MAGIC FAILS': CardScript(after: (x) async {
          if (!dark) return;
          if (willow.onBoard) await x.place(willow, x.zoneSpaces(willow), text: 'Move Willow to any space in her zone');
          await x.game.discardTopOfDeck(x.me);
        }),
        'REVOKE': cancelCard,
        'KNOWLEDGE OF THE CRAFT': CardScript(after: (x) async {
          if (!x.won) return;
          final c = await x.game.chooseCard(x.me, x.me.discard, 'Add a card from your discard pile to your hand', intent: Intent.gainOwn);
          if (c != null) await x.game.toHand(c);
        }),
        'MEDITATION': CardScript(after: (x) async {
          if (dark) await setDark(false);
        }),
        'RENDING SHOT': CardScript(after: (x) => pushOpponent(x, 3)),
      };
}
