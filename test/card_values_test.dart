// How a card's value is built: "this card's value is N instead" replaces the card's own value,
// and BOOSTs (and other additions) count on top of it whichever came first.
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/combat.dart';
import 'package:unmatched_game/engine/heroes/amaze.dart';
import 'package:unmatched_game/engine/prompt.dart';

import 'support.dart';

void main() {
  /// Medusa's Second Shot (printed 3) with [ops] on it.
  int valueWith(List<ValueOp> ops) {
    final s = Scenario('medusa', 'bigfoot');
    s.place(s.hero(s.p1), 4);
    s.place(s.hero(s.p2), 5);
    final side = Combat(s.hero(s.p1), s.hero(s.p2)).attacker..card = s.make(s.p1, 'Second Shot');
    side.ops.addAll(ops);
    final v = s.game.valueOf(side);
    expect(v.lines.fold(0, (a, l) => a + l.$2), v.total, reason: 'the breakdown adds up to the value');
    return v.total;
  }

  const boost = ValueOp.add(4, 'Boosted'), seven = ValueOp.set(7, 'Value is 7');

  test('a BOOST counts on top of "value is N instead", before or after it', () {
    expect(valueWith([boost, seven]), 11);
    expect(valueWith([seven, boost]), 11);
    expect(valueWith([boost, seven, const ValueOp.add(1, '+1')]), 12);
  });

  test('a later "value is N" replaces an earlier one, and keeps the BOOSTs', () {
    expect(valueWith([const ValueOp.set(5, 'Value is 5'), boost, seven]), 11);
  });

  test("a swapped total (Freyja's Rescue) replaces everything before it, BOOSTs included", () {
    expect(valueWith([boost, const ValueOp.total(6, 'Swapped')]), 6);
    expect(valueWith([boost, const ValueOp.total(6, 'Swapped'), const ValueOp.add(2, 'Later')]), 8);
  });

  test("Death Ray boosted through Tortoise Form, then 2 coils: 7 + the BOOST", () async {
    final s = Scenario('nikola-tesla', 'sun-wukong');
    final tesla = s.hero(s.p1), wukong = s.hero(s.p2);
    s.place(tesla, 4);
    s.place(wukong, 5);
    (s.p1.script as Tesla).coils = 2;
    s.give(s.p1, 'Death Ray'); // the second copy, to BOOST with (+4)
    // Whichever DURING COMBAT effect comes first: BOOST with Death Ray, discharge both coils.
    List<int> answer(Prompt p) => p.ask == Ask.option
        ? [p.choices.indexWhere((c) => c.label.startsWith('2 coils'))]
        : [p.choices.indexWhere((c) => (c.value as dynamic).title == 'Death Ray')];
    final c = await s.fight(tesla, wukong, 'Death Ray', 'Tortoise Form', then1: [answer, answer]);
    expect(c.attackValue, 11);
    expect(c.combatDamage, 11 - 5);
  });

  test('"equal to its printed value and cannot be changed" still ignores BOOSTs', () {
    final s = Scenario('medusa', 'bigfoot');
    s.place(s.hero(s.p1), 4);
    s.place(s.hero(s.p2), 5);
    final side = Combat(s.hero(s.p1), s.hero(s.p2)).attacker..card = s.make(s.p1, 'Second Shot');
    side.ops.addAll([boost, seven]);
    side.lockPrinted = true;
    expect(s.game.valueOf(side).total, 3);
  });
}
