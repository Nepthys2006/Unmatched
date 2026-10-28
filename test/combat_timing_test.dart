import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/combat.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/game.dart';

import 'support.dart';

void main() {
  test('Defender resolves IMMEDIATELY before Attacker IMMEDIATELY', () async {
    // Attacker King Arthur plays FEINT (versatile, immediately)
    // Defender Beowulf plays THE EQUAL OF GRENDEL (defense, immediately)
    final s = Scenario('king-arthur', 'beowulf');
    s.place(s.hero(s.p1), 5);
    s.place(s.hero(s.p2), 6);

    await s.fight(s.hero(s.p1), s.hero(s.p2), 'FEINT', 'THE EQUAL OF GRENDEL');

    final resolving = s.events.whereType<EffectResolving>().toList();
    expect(resolving, isNotEmpty);
    // Defender (Beowulf) resolves first in IMMEDIATELY window
    expect(resolving.first.side.isAttacker, isFalse);
    expect(resolving.first.timing, 'immediately');
    expect(resolving.first.side.fighter, s.hero(s.p2));
  });

  test('Defender resolves DURING COMBAT before Attacker DURING COMBAT', () async {
    // Both sides play cards with during combat effects
    // King Arthur and Alice both have MOMENTOUS SHIFT
    final s = Scenario('king-arthur', 'alice');
    s.place(s.hero(s.p1), 5);
    s.place(s.hero(s.p2), 6);
    s.game.turn.startSpace[s.hero(s.p1)] = 0; // moved this turn -> value 5
    s.game.turn.startSpace[s.hero(s.p2)] = 0; // moved this turn -> value 5

    await s.fight(s.hero(s.p1), s.hero(s.p2), 'MOMENTOUS SHIFT', 'MOMENTOUS SHIFT');

    final resolving = s.events.whereType<EffectResolving>().toList();
    // Defender resolves first in DURING window
    final duringEffects = resolving.where((e) => e.timing == 'during').toList();
    expect(duringEffects.length, 2);
    expect(duringEffects[0].side.isAttacker, isFalse);
    expect(duringEffects[1].side.isAttacker, isTrue);
  });

  test('Defender resolves AFTER COMBAT before Attacker AFTER COMBAT', () async {
    // Both play cards with AFTER COMBAT effects:
    // Medusa plays DASH (move up to 3)
    // King Arthur plays REGROUP (draw 1 card)
    final s = Scenario('king-arthur', 'medusa');
    s.place(s.hero(s.p1), 5);
    s.place(s.hero(s.p2), 6);

    await s.fight(s.hero(s.p1), s.hero(s.p2), 'REGROUP', 'DASH');

    final afterEffects = s.events.whereType<EffectResolving>().where((e) => e.timing == 'after').toList();
    expect(afterEffects.length, 2);
    expect(afterEffects[0].side.isAttacker, isFalse); // Defender DASH
    expect(afterEffects[1].side.isAttacker, isTrue); // Attacker REGROUP
  });

  test('Defender FEINT cancels Attacker DURING and AFTER effects', () async {
    // Attacker plays MOMENTOUS SHIFT (during)
    // Defender plays FEINT (immediately: cancel all effects)
    final s = Scenario('king-arthur', 'medusa');
    s.place(s.hero(s.p1), 5);
    s.place(s.hero(s.p2), 6);
    s.game.turn.startSpace[s.hero(s.p1)] = 0; // would be value 5 if not canceled

    final combat = await s.fight(s.hero(s.p1), s.hero(s.p2), 'MOMENTOUS SHIFT', 'FEINT');

    // Attacker effects were canceled
    expect(combat.attacker.canceled, isTrue);
    // Attacker during effect did NOT resolve
    final duringEffects = s.events.whereType<EffectResolving>().where((e) => e.timing == 'during').toList();
    expect(duringEffects, isEmpty);
    // Value remains printed base (3) rather than boosted (5)
    expect(combat.attackValue, 3);
  });

  test('Attacker FEINT cancels Defender AFTER, but Defender IMMEDIATELY still resolves', () async {
    // Attacker plays FEINT (immediately)
    // Defender plays THE EQUAL OF GRENDEL (immediately: draw 1 card)
    final s = Scenario('king-arthur', 'beowulf');
    s.place(s.hero(s.p1), 5);
    s.place(s.hero(s.p2), 6);

    final combat = await s.fight(s.hero(s.p1), s.hero(s.p2), 'FEINT', 'THE EQUAL OF GRENDEL');

    // Defender's IMMEDIATELY resolved first before attacker's Feint canceled the rest
    final resolving = s.events.whereType<EffectResolving>().toList();
    expect(resolving.any((e) => e.side.isAttacker == false && e.timing == 'immediately'), isTrue);
    // Defender card ends up marked canceled by Feint
    expect(combat.defender.canceled, isTrue);
  });

  test('Uncancelable cards ignore cancel effects', () async {
    // Beowulf's THE ANCIENT HEIRLOOM cannot be canceled
    // Opponent plays FEINT
    final s = Scenario('beowulf', 'medusa');
    s.place(s.hero(s.p1), 5);
    s.place(s.hero(s.p2), 6);

    final combat = await s.fight(s.hero(s.p1), s.hero(s.p2), 'THE ANCIENT HEIRLOOM', 'FEINT');

    // The uncancelable card is NOT canceled
    expect(combat.attacker.canceled, isFalse);
    expect(s.game.isUncancelable(combat.attacker), isTrue);
  });

  test('Value is X instead (ValueOp.set) overrides earlier boost, later boosts stack', () async {
    final s = Scenario('tomoe-gozen', 'medusa');
    final tomoe = s.hero(s.p1);
    final medusa = s.hero(s.p2);
    s.place(tomoe, 5);
    s.place(medusa, 6);

    // Side value setup
    final c = Combat(tomoe, medusa);
    c.attacker.card = s.give(s.p1, 'A WORTHY OPPONENT'); // Printed 3, if enemy is hero sets to 5
    // Add early boost
    s.game.addOp(c.attacker, const ValueOp.add(2, 'Early boost'));
    expect(s.game.valueOf(c.attacker).total, 5); // 3 + 2 = 5

    // Now apply "value is 5 instead"
    s.game.addOp(c.attacker, const ValueOp.set(5, 'A Worthy Opponent (Hero)'));
    expect(s.game.valueOf(c.attacker).total, 5); // Overwritten to 5

    // Now apply later boost +2
    s.game.addOp(c.attacker, const ValueOp.add(2, 'Later boost'));
    expect(s.game.valueOf(c.attacker).total, 7); // 5 + 2 = 7
  });

  test('Defeated fighter AFTER COMBAT effects do NOT resolve', () async {
    // 1. Sidekick defeated in combat: game continues, but defeated sidekick's after-combat effect does not run
    final s1 = Scenario('king-arthur', 'medusa');
    final harpy = s1.sidekick(s1.p2);
    s1.place(s1.hero(s1.p1), 5);
    s1.place(harpy, 6);
    s1.place(s1.hero(s1.p2), 10);
    harpy.hp = 1;

    // King Arthur attacks Harpy with EXCALIBUR (value 6)
    // Harpy defends with REGROUP (value 1, after: draw 1 card)
    // 6 - 1 = 5 damage dealt -> Harpy defeated!
    await s1.fight(s1.hero(s1.p1), harpy, 'EXCALIBUR', 'REGROUP');

    expect(harpy.defeated, isTrue);
    final afterEffects1 = s1.events.whereType<EffectResolving>().where((e) => e.timing == 'after').toList();
    // Defeated Harpy's after combat effect did NOT fire
    expect(afterEffects1.any((e) => e.side.fighter == harpy), isFalse);

    // 2. Hero defeated in combat: game over is checked ONLY after AFTER COMBAT window
    final s2 = Scenario('king-arthur', 'medusa');
    s2.place(s2.hero(s2.p1), 5);
    s2.place(s2.hero(s2.p2), 6);
    s2.hero(s2.p2).hp = 1;

    bool gameOverThrown = false;
    try {
      await s2.fight(s2.hero(s2.p1), s2.hero(s2.p2), 'EXCALIBUR', 'REGROUP');
    } on GameOverSignal {
      gameOverThrown = true;
    }

    expect(gameOverThrown, isTrue);
    expect(s2.hero(s2.p2).defeated, isTrue);
    final afterEffects2 = s2.events.whereType<EffectResolving>().where((e) => e.timing == 'after').toList();
    expect(afterEffects2.any((e) => e.side.fighter == s2.hero(s2.p2)), isFalse);
  });

  test('Houdini ALL PART OF THE SHOW resolves on defeat and revives him', () async {
    // Houdini with 2 HP plays ALL PART OF THE SHOW
    // Takes 6 damage from Excalibur -> defeated -> resolvesOnDefeat fires -> revived to 4 HP
    final s = Scenario('king-arthur', 'harry-houdini');
    s.place(s.hero(s.p1), 5);
    s.place(s.hero(s.p2), 6);
    s.hero(s.p2).hp = 2;

    // Houdini picks space 8 to revive
    await s.fight(s.hero(s.p1), s.hero(s.p2), 'EXCALIBUR', 'ALL PART OF THE SHOW', then2: [sp(8)]);

    expect(s.hero(s.p2).hp, 4);
    expect(s.hero(s.p2).defeated, isFalse);
    expect(s.hero(s.p2).space, 8);
  });

  test('Combat winner condition: attacker wins iff combatDamage > 0, otherwise defender wins', () async {
    // Test 1: Attacker deals 0 damage -> Defender wins
    final s1 = Scenario('king-arthur', 'medusa');
    s1.place(s1.hero(s1.p1), 5);
    s1.place(s1.hero(s1.p2), 6);
    final c1 = await s1.fight(s1.hero(s1.p1), s1.hero(s1.p2), 'FEINT', 'FEINT'); // 2 vs 2, 0 damage
    expect(c1.combatDamage, 0);
    expect(c1.attackerWon, isFalse);
    expect(c1.won(s1.p2), isTrue); // Defender won
    expect(c1.won(s1.p1), isFalse); // Attacker lost

    // Test 2: Attacker deals 1+ damage -> Attacker wins
    final s2 = Scenario('king-arthur', 'medusa');
    s2.place(s2.hero(s2.p1), 5);
    s2.place(s2.hero(s2.p2), 6);
    final c2 = await s2.fight(s2.hero(s2.p1), s2.hero(s2.p2), 'EXCALIBUR', 'FEINT'); // 6 vs 2, 4 damage
    expect(c2.combatDamage, 4);
    expect(c2.attackerWon, isTrue);
    expect(c2.won(s2.p1), isTrue); // Attacker won
    expect(c2.won(s2.p2), isFalse); // Defender lost
  });

  test('Bonus attack resolves against same defender with defender able to defend', () async {
    // Achilles plays TEST FOR WEAKNESS (after: bonus attack Relentless Assault 3)
    final s = Scenario('achilles', 'medusa');
    final achilles = s.hero(s.p1);
    final medusa = s.hero(s.p2);
    s.place(achilles, 5);
    s.place(medusa, 6);
    medusa.hp = 10;

    final a1 = s.agentOf(s.p1);
    final a2 = s.agentOf(s.p2);
    s.give(s.p1, 'TEST FOR WEAKNESS');
    a1.then(card('Test for Weakness'));
    // In first combat, defender defends with REGROUP (not Feint so after effect fires).
    s.give(s.p2, 'REGROUP');
    a2.then(card('Regroup'));
    // In bonus attack, defender defends with DASH.
    s.give(s.p2, 'DASH');
    a2.then(card('Dash'));

    await s.game.attack(achilles, medusa);

    // Two combats were resolved
    final combats = s.events.whereType<CombatResolved>().toList();
    expect(combats.length, 2);
    expect(combats[1].combat.attacker.card?.title, 'Relentless Assault');
    expect(combats[1].combat.attacker.card?.virtual, isTrue);
  });
}
