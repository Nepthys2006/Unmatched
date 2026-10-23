/// Cards printed in several decks with the same effect, plus small builders hero files reuse.
library;

import '../combat.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';

// ------------------------------------------------------------------------------- builders

/// AFTER COMBAT: Draw [n] cards.
CardScript drawAfter(int n) => CardScript(after: (x) => x.draw(n));

/// AFTER COMBAT: Move your fighter up to [n] spaces.
CardScript moveAfter(int n, {bool through = false}) => CardScript(after: (x) => x.move(x.fighter, n, throughOpp: through));

/// DURING COMBAT: You may BOOST this card.
const boostable = CardScript(during: _boost);
Future<void> _boost(Fx x) => x.boostThis();

/// IMMEDIATELY: Cancel all effects on your opponent's card.
const cancelCard = CardScript(immediately: _cancel);
Future<void> _cancel(Fx x) async => x.cancelOpponent();

/// No effects at all (vanilla cards like Excalibur).
const vanilla = CardScript(noEffects: true);

/// DURING COMBAT: If [test], this card's value is [v] instead.
CardScript valueIf(bool Function(Fx x) test, int v) => CardScript(during: (x) async {
      if (test(x)) x.setValue(v);
    });

/// IMMEDIATELY: The value of your opponent's card is equal to its printed value and cannot be changed.
final lockOpponent = CardScript(immediately: (x) async => x.oppSide.lockPrinted = true);

/// AFTER COMBAT: Your opponent discards [n] card(s).
CardScript oppDiscardsAfter(int n, {bool random = false, bool ifWon = false}) => CardScript(after: (x) async {
      if (!ifWon || x.won) await x.discard(x.opp, n, random: random);
    });

/// The opposing fighter moved by me "up to n".
Future<void> pushOpponent(Fx x, int n) async {
  if (x.oppFighter.onBoard) await x.move(x.oppFighter, n);
}

/// "Your opponent discards 1 random card. Add its BOOST value to this card's value."
Future<void> ambush(Fx x) async {
  final d = await x.discard(x.opp, 1, random: true);
  if (d.isNotEmpty) x.addValue(d.first.def.boost ?? 0, '${d.first.title} discarded (BOOST)');
}

/// "Discard the top card of your deck. Add its BOOST value to this card's value."
Future<Card?> discardTopAndAdd(Fx x) async {
  final c = await x.game.discardTopOfDeck(x.me);
  if (c != null) x.addValue(c.def.boost ?? 0, '${c.title} (BOOST)');
  return c;
}

/// "Look at your opponent's hand and choose 1 card for them to discard."
Future<void> pickDiscard(Fx x, {Player? target}) async {
  final t = target ?? x.opp;
  if (await x.game.lookAtHand(x.me, t)) await x.discard(t, 1, chooser: x.me);
}

/// Skirmish-style: "choose one of the fighters in the combat and move them up to n spaces".
Future<void> moveCombatant(Fx x, int n, {bool through = false}) async {
  final opts = [x.fighter, x.oppFighter].where((f) => f.onBoard);
  final f = await x.chooseFighter(opts, 'Choose a fighter in the combat to move up to $n', intent: Intent.none);
  if (f != null) await x.move(f, n, throughOpp: through);
}

/// "Deal n damage to each opposing fighter adjacent to [f]."
Future<void> damageAdjacentEnemies(Fx x, Fighter f, int n) async {
  for (final o in x.enemiesAdjacentTo(f).toList()) {
    await x.damage(o, n);
  }
}

/// Opposing fighters of [x.me] in [f]'s zone.
Iterable<Fighter> enemiesInZone(Fx x, Fighter f) => x.inZoneOf(f).where((o) => o.isEnemyOf(x.me));

/// The other fighters of [x.me] adjacent to [target].
int friendsAdjacentTo(Fx x, Fighter target, {Fighter? except}) =>
    x.adjacentTo(target).where((o) => o.isFriendOf(x.me) && o != except).length;

/// "Do My Bidding": return the opponent's attack card, look at their hand, choose what they play.
Future<void> doMyBidding(Fx x) async {
  final s = x.oppSide;
  // A bonus attack is not a card, so it can't be returned to a hand.
  if (s.card == null || !s.isAttacker || s.card!.virtual) return;
  final g = x.game;
  final attackerF = s.fighter;
  await g.replaceCard(s, null);
  final looked = await g.lookAtHand(x.me, x.opp);
  final opts = x.opp.hand.where((c) => g.canAttackWith(c, attackerF)).toList();
  if (opts.isEmpty) return;
  final pick = looked
      ? await g.chooseCard(x.me, opts, 'Choose an attack for ${x.opp.name} to play', intent: Intent.forceEnemy)
      : opts.first;
  await g.replaceCard(s, pick);
}

/// "Move each of [fighters] up to n spaces", in the order the player picks.
Future<void> moveEach(Fx x, Iterable<Fighter> fighters, int n, {bool through = false}) async {
  final left = fighters.where((f) => f.onBoard).toList();
  while (left.isNotEmpty) {
    final f = left.length == 1
        ? left.first
        : await x.chooseFighter(left, 'Choose a fighter to move up to $n (or finish)', optional: true);
    if (f == null) break;
    left.remove(f);
    if (f.onBoard) await x.move(f, n, throughOpp: through);
  }
}

/// Picks [k] different options from [options], one at a time; returns their indices in order.
Future<List<int>> chooseDifferent(Fx x, List<String> options, int k, String text) async {
  final left = [for (var i = 0; i < options.length; i++) i];
  final out = <int>[];
  for (var n = 0; n < k && left.isNotEmpty; n++) {
    final i = await x.option([for (final j in left) options[j]], '$text (${n + 1} of $k)');
    out.add(left.removeAt(i));
  }
  return out;
}

// --------------------------------------------------------------------------------- library

final Map<String, CardScript> commonCardScripts = {
  'FEINT': cancelCard,
  'PARRY': cancelCard,
  'IMPOSING PRESENCE': cancelCard,
  "IT'S JUST YOUR IMAGINATION": cancelCard,
  'REGROUP': CardScript(after: (x) => x.draw(x.won ? 2 : 1)),
  'SKIRMISH': CardScript(after: (x) async {
    if (x.won) await moveCombatant(x, 2);
  }),
  'LEAP AWAY': CardScript(after: (x) async {
    if (x.won) await moveCombatant(x, 4);
  }),
  'MOMENTOUS SHIFT': valueIf((x) => x.game.startedTurnElsewhere(x.fighter), 5),
  'DASH': moveAfter(3),
  'SWIFT STRIKE': moveAfter(4),
  'SNIPE': drawAfter(1),
  'EXPLOIT': drawAfter(1),
  'QUICK STRIKE': drawAfter(1),
  'COMMANDING IMPACT': drawAfter(1),
  'WILY FIGHTING': CardScript(after: (x) => damageAdjacentEnemies(x, x.fighter, 1)),
  'BEWILDERMENT': CardScript(
    during: (x) async => x.combat.flags['preventAll'] = true,
    after: (x) async {
      if (x.fighter.onBoard) await x.place(x.fighter, x.allSpaces, text: 'You may place ${x.fighter.name} in any space', optional: true);
    },
  ),
  'LONG SHOT': valueIf((x) => !x.adjacent(x.fighter, x.oppFighter), 5),
  'SAVAGERY': CardScript(after: (x) async {
    if (!x.won) return;
    for (final f in x.adjacentTo(x.fighter).toList()) {
      await x.damage(f, 1);
    }
  }),
  'AMBUSH': const CardScript(during: ambush),
  'TURTLE POWER!': boostable,
  'HEROES IN A HALF SHELL': vanilla,
  'PARALYZING FETTERS': lockOpponent,
  'DISRUPTING STRIKE': lockOpponent,
  'DO MY BIDDING': const CardScript(immediately: doMyBidding),
  'REGICIDE': valueIf((x) => x.oppFighter.isHero, 6),
  'CLAWS THAT CATCH': valueIf((x) => x.oppFighter.isHero, 5),
};

/// Value shorthand used by several files.
extension SideValue on Side {
  int get printedValue => card?.def.value ?? 0;
}
