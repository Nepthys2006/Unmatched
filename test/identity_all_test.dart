// Every hero's identity card, checked through the real game setup: fighters and their health,
// attack type and move, starting positions, starting hand and deck, the identity card and
// avatar images; then a whole match with that hero is played to the end.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';

import 'support.dart';

/// Identity card values that a hero's ability changes on purpose.
const _moveAtStart = {'krang': 2}; // move 1 + 1 per active doomsday machine (1 at the start)
const _handAtStart = {'black-widow': 6, 'michelangelo': 3}; // Moscow Protocol added; hand size 3

/// Official deck sizes other than 30 (Hell's Kitchen decks are smaller; Black Widow's 31 counts
/// The Moscow Protocol).
const _deckSize = {'daredevil': 22, 'elektra': 20, 'black-widow': 31};

/// Heroes who choose one sidekick before the game (the other one is left out).
const _chooseSidekick = {'yennefer-triss', 'buffy'};

void main() {
  final data = loadData();
  final heroes = data.heroes.keys.toList()..sort();

  test('all 70 heroes are scripted', () {
    expect(heroes, hasLength(70));
    expect(heroes.where((h) => !isImplemented(h)), isEmpty);
  });

  for (final id in heroes) {
    test('$id: identity card through setup, then a full match', () async {
      final hero = data.hero(id);
      final map = data.mapsFor('1v1').first;
      final g = Game(
        data: data,
        map: map,
        heroIds: [id, 'medusa'],
        agents: [AiAgent(level: AiLevel.hard, seed: 1), AiAgent(level: AiLevel.hard, seed: 2)],
        seed: 7,
        firstSeat: 0,
      );
      await g.setup();
      final p = g.players[0];

      // Images.
      for (final asset in [hero.identity, hero.avatar]) {
        expect(File(asset).existsSync(), isTrue, reason: '$asset is missing');
      }
      expect(hero.ability.trim(), isNotEmpty);

      // Fighters: how many, health, attack type.
      for (final d in hero.fighters) {
        final made = p.fighters.where((f) => f.def == d).toList();
        if (_chooseSidekick.contains(id) && !d.isHero) {
          expect(made.length, lessThanOrEqualTo(d.count), reason: 'only the chosen sidekick plays');
          continue;
        }
        expect(made, hasLength(d.count), reason: '${d.name} count');
        for (final f in made) {
          expect(f.maxHp, d.hp, reason: '${f.name} starting health');
          expect(f.hp, d.hp, reason: '${f.name} health at the start');
          expect(f.attack, d.attack, reason: '${f.name} attack type');
        }
      }

      // Move value of the hero at the start.
      expect(g.moveValueOf(p.heroFighter), _moveAtStart[id] ?? hero.move, reason: 'move');

      // Positions: the hero on its start space; fighters on the board each have a space
      // (small fighters may share one), sidekicks in the hero's zone or off the board.
      expect(p.heroFighter.space, p.startSpace);
      final spaces = <int>{};
      for (final f in p.onBoard) {
        if (!f.isSmall) expect(spaces.add(f.space!), isTrue, reason: 'two fighters on space ${f.space}');
      }
      for (final f in p.fighters.where((f) => f.isSidekick)) {
        expect(f.onBoard || f.reserve, isTrue, reason: '${f.name} is placed or waiting off the board');
      }

      // Starting hand and deck.
      final total = p.script.deckCards().length;
      expect(p.hand, hasLength(_handAtStart[id] ?? 5), reason: 'starting hand');
      expect(p.deck.length + p.hand.length, total, reason: 'deck + hand = whole deck');
      expect(total, _deckSize[id] ?? 30, reason: 'deck size once pre-game choices are made');

      // And a whole match plays to a winner.
      final g2 = Game(
        data: data,
        map: map,
        heroIds: [id, 'medusa'],
        agents: [AiAgent(level: AiLevel.hard, seed: 3), AiAgent(level: AiLevel.hard, seed: 4)],
        seed: 11,
      );
      final winner = await g2.run();
      expect(winner, isNotNull);
      expect(g2.over, isTrue);
    });
  }
}
