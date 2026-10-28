// Schemes with several opponents (free-for-all, teams): a card aimed at "your opponent" asks
// which one; a card that hits "each opponent" asks nothing and hits them all.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';

import 'support.dart';

bool askedForOpponent(ScriptedAgent a) => a.asked.any((p) => p.text.toLowerCase().contains('choose an opponent'));

void main() {
  Scenario three(String hero) {
    final s = Scenario(hero, 'medusa', hero3: 'king-arthur');
    s.place(s.hero(s.p1), 0);
    s.place(s.hero(s.p2), 11);
    s.place(s.hero(s.p3), 6);
    for (final o in [s.p2, s.p3]) {
      s.give(o, o.hero.cards[0].title);
      s.give(o, o.hero.cards[1].title);
      s.give(o, o.hero.cards[2].title);
    }
    return s;
  }

  test('Louisville Lip after a won combat: each opponent discards, nobody is asked which', () async {
    final s = three('muhammad-ali');
    s.game.turn.flags['aliWon'] = true;
    await s.game.playScheme(s.p1, s.give(s.p1, 'Louisville lip'));
    expect(askedForOpponent(s.a1), isFalse);
    expect(s.p2.hand, hasLength(2));
    expect(s.p3.hand, hasLength(2));
    expect(s.p2.discard, hasLength(1));
    expect(s.p3.discard, hasLength(1));
  });

  test('The Budapest Gambit: each opponent discards 1 random card, no opponent to choose', () async {
    final s = three('black-widow');
    s.p1.hand.clear();
    await s.game.playScheme(s.p1, s.give(s.p1, 'The Budapest Gambit'));
    expect(askedForOpponent(s.a1), isFalse);
    expect([s.p2.hand.length, s.p3.hand.length], [2, 2]);
  });

  test('Eliminate the Impossible: you choose the opponent, then the card they discard', () async {
    final s = three('sherlock-holmes');
    final target = s.p3.hand[1];
    s.a1
      ..then(s.p3.name)
      ..then(card(target.def.title));
    await s.game.playScheme(s.p1, s.give(s.p1, 'Eliminate the Impossible'));
    expect(askedForOpponent(s.a1), isTrue);
    expect(s.p3.discard, [target]);
    expect(s.p3.hand, hasLength(2));
    expect(s.p2.hand, hasLength(3), reason: 'the other opponent keeps their cards');
    expect(s.p2.discard, isEmpty);
  });

  test('every scheme that only says "each opponent" asks no opponent; one aimed at "your opponent" does', () {
    final data = loadData();
    final eachOnly = <String>[], aimed = <String>[];
    for (final h in data.heroes.values.where((h) => isImplemented(h.id))) {
      for (final c in h.cards.where((c) => c.type.name == 'scheme')) {
        final text = c.text.values.join(' ').toLowerCase();
        if (!text.contains('opponent')) continue;
        final rest = text.replaceAll(RegExp(r'each opponent|all opponents|opponents\b'), '');
        (rest.contains('opponent') ? aimed : eachOnly).add('${h.id}: ${c.title}');
      }
    }
    // The cards found by the scan above (so a data change shows up here).
    expect(eachOnly, containsAll(['muhammad-ali: Louisville lip', 'black-widow: The Budapest Gambit', 'winter-soldier: Manipulation']));
    expect(aimed, containsAll(['sherlock-holmes: Eliminate the Impossible', 'buffy: Insight']));
  });
}
