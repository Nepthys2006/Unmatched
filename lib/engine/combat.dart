/// Combat state: the two sides, their cards and how each card's value is built up.
library;

import 'state.dart';

enum Phase { choose, reveal, immediately, during, damage, after, done }

/// One change to a card's value. "This card's value is 5 instead" ([ValueOp.set]) replaces the
/// card's own value only: BOOSTs and other additions ([ValueOp.add]) count on top of it whether
/// they came before or after. [ValueOp.total] replaces the whole value built so far (Freyja's
/// Rescue swaps the two cards' values); additions after it still count.
class ValueOp {
  const ValueOp.add(this.amount, this.label)
      : isSet = false,
        isTotal = false;
  const ValueOp.set(this.amount, this.label)
      : isSet = true,
        isTotal = false;
  const ValueOp.total(this.amount, this.label)
      : isSet = true,
        isTotal = true;
  final int amount;

  /// Sets the value ([ValueOp.set] or [ValueOp.total]) rather than adding to it.
  final bool isSet;
  final bool isTotal;
  final String label;
}

class Side {
  Side(this.combat, this.isAttacker, this.fighter);

  final Combat combat;
  final bool isAttacker;
  Fighter fighter;
  Card? card;

  /// All effects on the card are canceled (only if the card had effects that could be canceled).
  bool canceled = false;

  /// Only the AFTER COMBAT effects are canceled.
  bool afterCanceled = false;

  /// The DURING COMBAT effects are canceled too (Break Something), but not IMMEDIATELY.
  bool duringCanceled = false;
  final List<ValueOp> ops = [];

  /// "Ignore the value": the card counts as 0.
  bool ignored = false;

  /// "Equal to its printed value and cannot be changed".
  bool lockPrinted = false;

  /// "Value is 0 and cannot be changed by card effects".
  bool lockZero = false;

  /// Replaces the printed value (Deduce Strategy, This Is No Parlor Trick).
  int? printedOverride;

  /// Cards discarded to boost this card.
  final List<Card> boosts = [];
  bool faceUp = false;

  /// Per-card scratch values (a prediction, a discarded card...).
  final Map<String, Object?> vars = {};

  Player get player => fighter.owner;
  Side get other => isAttacker ? combat.defender : combat.attacker;
  bool get hasCard => card != null;
  int get printed => printedOverride ?? card?.def.value ?? 0;

  void clearCard() {
    ops.clear();
    boosts.clear();
    canceled = false;
    afterCanceled = false;
    duringCanceled = false;
    printedOverride = null;
    vars.clear();
  }

  @override
  String toString() => '${isAttacker ? 'attacker' : 'defender'} ${fighter.name} with ${card?.title ?? '-'}';
}

class Combat {
  Combat(Fighter att, Fighter def) {
    attacker = Side(this, true, att);
    defender = Side(this, false, def);
  }

  late final Side attacker;
  late final Side defender;
  Phase phase = Phase.choose;

  /// Combat damage the attack dealt to the defending fighter (after prevention/redirection).
  int combatDamage = 0;
  int attackValue = 0;
  int defenseValue = 0;
  bool attackerWon = false;
  bool resolved = false;

  /// Combat-wide flags: 'preventAll', 'reflect' and so on.
  final Map<String, Object?> flags = {};

  /// The attack card's printed value the defender was told before choosing a defense card
  /// (Spider-Man's Spidey-Sense), or null if they weren't told.
  int? toldAttackValue;

  Side sideOf(Player p) => attacker.player == p ? attacker : defender;
  Side sideOfFighter(Fighter f) => attacker.fighter == f ? attacker : defender;
  bool involves(Fighter f) => attacker.fighter == f || defender.fighter == f;
  /// Whether [p] won. Also true when an effect says they are "considered to have won"
  /// (flags['alsoWon'], Bullseye's Arrogant But Effective).
  bool won(Player p) => resolved && ((attackerWon ? attacker.player == p : defender.player == p) || flags['alsoWon'] == p);
  Iterable<Side> get sides => [defender, attacker];
}
