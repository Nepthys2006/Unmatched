// The opening-hand mulligan: once per player per game, shuffle the whole hand back and draw the
// same number of cards, the new hand is final, and the AI takes it when its hand has few combat
// cards. Also covers every playable hero (hand sizes differ, Black Widow's mission starts in hand).
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/defs.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

/// Takes the first choice of every setup question (placing sidekicks, Alice's size...) and
/// answers the mulligan by its label, whatever else was asked before it.
class SetupAgent implements Agent {
  SetupAgent(this.mulligan);
  final String mulligan;
  final List<Prompt> asked = [];
  int others = 0;

  @override
  Future<List<int>> decide(Game game, Prompt p) async {
    if (p.intent == Intent.mulligan) {
      asked.add(p);
      return [p.choices.indexWhere((c) => c.label == mulligan)];
    }
    others++;
    return p.optional ? const [] : const [0];
  }
}

/// A game with [mulligans] switched on, set up (hands drawn, mulligans offered) and not played on.
/// [first] and [second] are the labels the two players answer the mulligan with.
Future<(Game, List<SetupAgent>, List<GameEvent>)> setUp2(
  String a,
  String b, {
  int seed = 1,
  bool mulligans = true,
  String first = 'Keep Hand',
  String second = 'Keep Hand',
}) async {
  final agents = [SetupAgent(first), SetupAgent(second)];
  final events = <GameEvent>[];
  final game = Game(
    data: loadData(),
    map: lineMap(),
    heroIds: [a, b],
    agents: agents,
    seed: seed,
    firstSeat: 0,
    mulligans: mulligans,
    presenter: (e) async => events.add(e),
  );
  await game.setup();
  return (game, agents, events);
}

int total(Player p) => p.deck.length + p.hand.length;

void main() {
  test('off by default: no prompt, five cards in hand', () async {
    final (g, agents, events) = await setUp2('alice', 'medusa', mulligans: false);
    expect(agents[0].asked, isEmpty);
    expect(g.players[0].hand, hasLength(5));
    expect(events.whereType<Mulliganed>(), isEmpty);
  });

  test('every player is offered it once, Mulligan or Keep Hand', () async {
    final (g, agents, events) = await setUp2('alice', 'medusa');
    for (final a in agents) {
      expect(a.asked, hasLength(1));
      final p = a.asked.single;
      expect(p.ask, Ask.option);
      expect(p.intent, Intent.mulligan);
      expect([for (final c in p.choices) c.label], ['Mulligan', 'Keep Hand']);
    }
    expect(events.whereType<Mulliganed>(), hasLength(2));
    expect(g.players.every((p) => p.mulliganUsed), isTrue);
  });

  test('Keep Hand leaves the hand and the deck as they were', () async {
    final (g, _, events) = await setUp2('alice', 'medusa');
    final drawn = events.whereType<CardsDrawn>().where((e) => e.player == g.players[0]).single.cards;
    expect(g.players[0].hand, drawn);
    expect(events.whereType<Mulliganed>().every((e) => !e.took), isTrue);
  });

  test('Mulligan shuffles the whole hand back and draws the same number, nothing lost or duplicated', () async {
    var differed = 0;
    for (var seed = 1; seed <= 20; seed++) {
      final (g, _, events) = await setUp2('alice', 'medusa', seed: seed, first: 'Mulligan');
      final p = g.players[0];
      final before = events.whereType<CardsDrawn>().first.cards.map((c) => c.uid).toSet();
      expect(p.hand, hasLength(5), reason: 'same size');
      expect(total(p), p.hero.deckSize, reason: 'no card lost');
      final all = [...p.hand, ...p.deck].map((c) => c.uid).toList();
      expect(all.toSet(), hasLength(all.length), reason: 'no card twice');
      if (p.hand.map((c) => c.uid).toSet().difference(before).isNotEmpty) differed++;
      final took = events.whereType<Mulliganed>().first;
      expect(took.took, isTrue);
      expect(took.log, contains('mulligan'));
    }
    expect(differed, greaterThan(15), reason: 'a new hand, not the same one back');
  });

  test('only once: a second offer asks nothing and changes nothing', () async {
    final (g, agents, _) = await setUp2('alice', 'medusa', first: 'Mulligan');
    final p = g.players[0];
    final hand = List.of(p.hand);
    await g.offerMulligan(p);
    expect(agents[0].asked, hasLength(1));
    expect(p.hand, hand);
  });

  test('the new hand is final even after pressing Mulligan', () async {
    final (g, agents, _) = await setUp2('alice', 'medusa', first: 'Mulligan');
    expect(agents[0].asked, hasLength(1), reason: 'it is never asked a second time');
    expect(g.players[0].hand, hasLength(5));
  });

  test("Black Widow's mission starts in hand again after a mulligan, hand size kept", () async {
    for (var seed = 1; seed <= 10; seed++) {
      final (g, _, _) = await setUp2('black-widow', 'medusa', seed: seed, first: 'Mulligan');
      final p = g.players[0];
      expect(p.hand, hasLength(6));
      expect(p.hand.where((c) => c.def.upperTitle == 'THE MOSCOW PROTOCOL'), hasLength(1));
      expect(total(p), p.hero.deckSize);
    }
  });

  test('every playable hero: mulligan keeps the hand size and every card, whatever the starting hand', () async {
    final heroes = loadData().heroes.keys.where(isImplemented).toList()..sort();
    expect(heroes.length, greaterThan(60));
    for (var i = 0; i < heroes.length; i++) {
      final h = heroes[i], foe = heroes[(i + 1) % heroes.length];
      final (g, _, events) = await setUp2(h, foe, seed: i + 1, first: 'Mulligan', second: 'Mulligan');
      for (final p in g.players) {
        final first = events.whereType<CardsDrawn>().firstWhere((e) => e.player == p).cards.length;
        expect(p.hand, hasLength(first), reason: '${p.hero.id}: same size');
        expect(p.mulliganUsed, isTrue, reason: p.hero.id);
        final all = [...p.hand, ...p.deck].map((c) => c.uid).toList();
        expect(all.toSet(), hasLength(all.length), reason: '${p.hero.id}: no card twice');
      }
    }
  });

  group('the AI', () {
    // The hero with the most scheme cards, so a hand of nothing but schemes can be dealt.
    final schemeHero = (loadData().heroes.values.where((h) => isImplemented(h.id)).toList()
          ..sort((a, b) => b.cards.where((c) => c.isScheme).fold(0, (n, c) => n + c.copies).compareTo(a.cards.where((c) => c.isScheme).fold(0, (n, c) => n + c.copies))))
        .first
        .id;

    Future<(Game, Prompt)> aiHand(List<CardType> types) async {
      final (g, _, _) = await setUp2(schemeHero, 'medusa', mulligans: false);
      final p = g.players[0];
      // A hand of exactly these card types, taken from the deck.
      p.deck.addAll(p.hand);
      p.hand.clear();
      for (final t in types) {
        final c = p.deck.firstWhere((c) => c.def.type == t);
        p.deck.remove(c);
        p.hand.add(c);
      }
      final prompt = Prompt(
        player: p,
        ask: Ask.option,
        text: 'Opening hand',
        choices: const [Choice('Mulligan', 0), Choice('Keep Hand', 1)],
        intent: Intent.mulligan,
      );
      return (g, prompt);
    }

    test('mulligans a hand with almost no attack or defense cards', () async {
      final (g, prompt) = await aiHand([CardType.scheme, CardType.scheme, CardType.scheme, CardType.scheme, CardType.attack]);
      for (final level in AiLevel.values.where((l) => l != AiLevel.easy)) {
        expect(await AiAgent(level: level, seed: 1).decide(g, prompt), [0], reason: level.name);
      }
    });

    test('keeps a hand with attack and defense cards', () async {
      final (g, prompt) = await aiHand([CardType.attack, CardType.defense, CardType.versatile, CardType.scheme, CardType.attack]);
      for (final level in AiLevel.values) {
        expect(await AiAgent(level: level, seed: 1).decide(g, prompt), [1], reason: level.name);
      }
    });

    test('Easy only throws back a hand with no combat card at all', () async {
      final (g, none) = await aiHand([CardType.scheme, CardType.scheme, CardType.scheme, CardType.scheme, CardType.scheme]);
      expect(await AiAgent(level: AiLevel.easy, seed: 1).decide(g, none), [0]);
      final (g2, one) = await aiHand([CardType.scheme, CardType.scheme, CardType.scheme, CardType.scheme, CardType.attack]);
      expect(await AiAgent(level: AiLevel.easy, seed: 1).decide(g2, one), [1]);
    });

    test('whole games with mulligans on still play to the end, at every level', () async {
      for (final level in AiLevel.values) {
        final game = Game(
          data: loadData(),
          map: lineMap(),
          heroIds: const ['alice', 'medusa'],
          agents: [AiAgent(level: level, seed: 3), AiAgent(level: level, seed: 4)],
          seed: 7,
          mulligans: true,
        );
        final winner = await game.run().timeout(const Duration(seconds: 60));
        expect(winner, isNotNull, reason: level.name);
        expect(game.players.every((p) => p.mulliganUsed), isTrue);
      }
    });
  });
}
