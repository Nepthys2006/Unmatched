// The UMCCC Model: the trained search AI offered next to the four AI levels. Covers the model file,
// the search playing whole matches with every implemented hero, and the setup screen's fifth tile.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/engine/game.dart';
import 'package:unmatched_game/engine/heroes/registry.dart';
import 'package:unmatched_game/engine/ismcts/evaluator.dart';
import 'package:unmatched_game/engine/ismcts/features.dart';
import 'package:unmatched_game/engine/ismcts/ismcts.dart';
import 'package:unmatched_game/engine/ismcts/ismcts_agent.dart';
import 'package:unmatched_game/engine/events.dart';
import 'package:unmatched_game/engine/prompt.dart';
import 'package:unmatched_game/ui/match/match_config.dart';
import 'package:unmatched_game/ui/screens/setup_screen.dart';

import 'support.dart';
import 'widget_test.dart' show boot, desktop, loadFonts, phone, pumpUntil, smallPhone;

class _TooLong implements Exception {}

LearnedEvaluator loadModel() => LearnedEvaluator.fromString(File('assets/ai/umccc_model.json').readAsStringSync());

void main() {
  setUpAll(loadFonts);

  group('model file', () {
    test('loads, and its inputs match what the engine produces for the app\'s heroes', () async {
      final model = loadModel();
      expect(model.featureVersion, StateFeatures.version);
      expect(model.heroIndex, isNotNull);
      expect(model.heroIndex!.length, 70);

      final data = loadData();
      final game = Game(
        data: data,
        map: data.mapsFor('1v1').first,
        heroIds: ['achilles', 'medusa'],
        agents: [AiAgent(level: AiLevel.insane), AiAgent(level: AiLevel.insane)],
        random: Random(1),
      );
      await game.setup();
      final score = model.evaluate(game, game.players[0]);
      expect(score, inInclusiveRange(-1.0, 1.0));
      // Every implemented hero has an input slot in the model.
      for (final id in data.heroes.keys.where(isImplemented)) {
        expect(model.heroIndex!.containsKey(id), isTrue, reason: '$id has no slot in the model');
      }
    });

    test('is a roughly balanced judge: the same position is worth about the opposite to the other side', () async {
      final model = loadModel();
      final data = loadData();
      final game = Game(
        data: data,
        map: data.mapsFor('1v1').first,
        heroIds: ['bigfoot', 'medusa'],
        agents: [AiAgent(level: AiLevel.insane), AiAgent(level: AiLevel.insane)],
        random: Random(2),
      );
      await game.setup();
      final a = model.evaluate(game, game.players[0]);
      final b = model.evaluate(game, game.players[1]);
      expect((a + b).abs(), lessThan(1.0), reason: 'a=$a b=$b');
    });
  });

  group('the search plays real matches', () {
    // Every implemented hero plays against the UMCCC Model at least once, half the games with the
    // cooperative (UI-friendly) search that yields between slices, half flat out.
    test('with every implemented hero, without engine errors', () async {
      final data = loadData();
      final model = loadModel();
      final heroes = data.heroes.keys.where(isImplemented).toList()..shuffle(Random(11));
      final map = data.mapsFor('1v1').first;
      final failedBefore = IsmctsEngine.failedSims;
      final totalBefore = IsmctsEngine.totalSims;
      var finished = 0;

      for (var i = 0; i + 1 < heroes.length; i += 2) {
        final umccc = IsmctsAgent(
          level: AiLevel.insane,
          subPromptLevel: AiLevel.insane,
          evaluator: model,
          customBudget: const IsmctsBudget(maxSimulations: 12),
          useBackgroundIsolate: (i ~/ 2).isEven, // cooperative search on half of the games
          seed: i,
        );
        final seat = (i ~/ 2) % 2; // the UMCCC Model sits in either seat
        late Game game;
        game = Game(
          data: data,
          map: map,
          heroIds: [heroes[i], heroes[i + 1]],
          agents: [seat == 0 ? umccc : AiAgent(level: AiLevel.insane, seed: i), seat == 1 ? umccc : AiAgent(level: AiLevel.insane, seed: i + 1)],
          random: Random(i + 100),
          presenter: (GameEvent e) async {
            umccc.observeEvent(e);
            if (game.turnNumber > 150) throw _TooLong();
          },
        );
        final winner = await game.run();
        expect(winner, isNotNull, reason: '${heroes[i]} vs ${heroes[i + 1]} ended without a winner');
        finished++;
      }

      expect(finished, greaterThanOrEqualTo(30));
      final sims = IsmctsEngine.totalSims - totalBefore;
      final failed = IsmctsEngine.failedSims - failedBefore;
      expect(sims, greaterThan(0), reason: 'the search never ran');
      expect(failed / sims, lessThan(0.05), reason: '$failed of $sims simulations hit an engine error');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('hard and insane budgets finish a move within the time cap', () async {
      final data = loadData();
      final model = loadModel();
      for (final budget in [IsmctsBudget.hard, IsmctsBudget.insane]) {
        final agent = IsmctsAgent(
          level: AiLevel.insane,
          subPromptLevel: AiLevel.insane,
          evaluator: model,
          customBudget: budget,
          useBackgroundIsolate: true,
          seed: 3,
        );
        final slowest = <int>[];
        late Game game;
        game = Game(
          data: data,
          map: data.mapsFor('1v1').first,
          heroIds: ['achilles', 'dracula'],
          agents: [_Timed(agent, slowest), AiAgent(level: AiLevel.insane, seed: 4)],
          random: Random(9),
          presenter: (e) async {
            agent.observeEvent(e);
            if (game.turnNumber > 150) throw _TooLong();
          },
        );
        await game.run();
        slowest.sort();
        // The cap is a budget for the search; allow the finishing move and slow test machines.
        expect(slowest.last, lessThan(budget.timeLimit!.inMilliseconds * 3), reason: 'moves took $slowest');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('setup screen', () {
    // Phones, tablets and desktops (logical sizes, landscape as the app is played).
    const devices = <String, Size>{
      'small phone 740x360': smallPhone,
      'iPhone SE 667x375': Size(667, 375),
      'iPhone 14 844x390': Size(844, 390),
      'Pixel 7 915x412': phone,
      'big phone 960x440': Size(960, 440),
      'iPad 1024x768': Size(1024, 768),
      'iPad Pro 1366x1024': Size(1366, 1024),
      'Android tablet 1280x800': Size(1280, 800),
      'laptop 1366x768': Size(1366, 768),
      'desktop 1440x900': desktop,
    };
    for (final e in devices.entries) {
      final size = e.value;
      testWidgets('UMCCC Model is a fifth opponent, 1 v 1 only, and the four AIs are still there (${e.key})', (t) async {
        await boot(t, size, home: const SetupScreen());
        await pumpUntil(t, () => find.text('UMCCC MODEL').evaluate().isNotEmpty);

        for (final l in ['EASY', 'MEDIUM', 'HARD', 'INSANE', 'UMCCC MODEL']) {
          expect(find.text(l), findsOneWidget, reason: l);
        }
        bool summaryHas(String s) => find
            .byWidgetPredicate((w) => w is Text && (w.data ?? '').toLowerCase().contains(s.toLowerCase()))
            .evaluate()
            .isNotEmpty;

        expect(summaryHas('AI Medium'), isTrue, reason: 'the default stays Medium');
        await t.tap(find.text('UMCCC MODEL'));
        await t.pump();
        expect(summaryHas('AI UMCCC Model'), isTrue);

        // Picking one of the four goes back to it.
        await t.tap(find.text('HARD'));
        await t.pump();
        expect(summaryHas('AI Hard'), isTrue);
        expect(summaryHas('AI UMCCC Model'), isFalse);

        // Team modes: the tile is off, and leaving 1 v 1 drops a UMCCC choice.
        await t.tap(find.text('UMCCC MODEL'));
        await t.pump();
        expect(summaryHas('AI UMCCC Model'), isTrue);
        await t.tap(find.text('2 V 2'));
        await t.pump();
        expect(summaryHas('AI UMCCC Model'), isFalse);
        expect(find.text('Available in 1 v 1 only.'), findsOneWidget);
        await t.tap(find.text('UMCCC MODEL'));
        await t.pump();
        expect(summaryHas('AI UMCCC Model'), isFalse, reason: 'the disabled tile must not select');
        expect(t.takeException(), isNull);
      });
    }
  });

  test('a MatchConfig keeps the UMCCC flag through a rematch', () {
    final data = loadData();
    final cfg = MatchConfig(
      mode: GameMode.duel,
      players: 2,
      map: data.mapsFor('1v1').first,
      ai: AiLevel.insane,
      heroIds: ['achilles', 'medusa'],
      umccc: true,
    );
    expect(cfg.aiLabel, umcccLabel);
    expect(cfg.rematch().umccc, isTrue);
    expect(MatchConfig(mode: GameMode.duel, players: 2, map: cfg.map, ai: AiLevel.hard, heroIds: cfg.heroIds).aiLabel, 'Hard');
  });
}

class _Timed implements Agent {
  _Timed(this.inner, this.ms);
  final Agent inner;
  final List<int> ms;

  @override
  Future<List<int>> decide(Game game, Prompt prompt) async {
    final sw = Stopwatch()..start();
    final r = await inner.decide(game, prompt);
    ms.add(sw.elapsedMilliseconds);
    return r;
  }
}
