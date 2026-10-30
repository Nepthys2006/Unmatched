import 'dart:math';

import '../ai.dart';
import '../events.dart';
import '../game.dart';
import '../prompt.dart';
import 'determinizer.dart';
import 'evaluator.dart';
import 'ismcts.dart';
import 'runner_isolate.dart';
import 'runner_web.dart';

/// Information Set Monte Carlo Tree Search agent.
///
/// The search chooses the turn actions (maneuver / scheme / attack), where a wrong move costs
/// the most. The follow-up prompts inside an action (which card to play, where to move, whom to
/// target...) are answered by the heuristic [AiAgent] at the same difficulty, because the
/// engine cannot be resumed in the middle of an action to search them.
class IsmctsAgent implements Agent {
  IsmctsAgent({
    this.level = AiLevel.medium,
    Evaluator? evaluator,
    int? seed,
    this.isWeb = false,
    this.useBackgroundIsolate = true,
    IsmctsBudget? customBudget,
    AiLevel? subPromptLevel,
    this.rolloutTurns = 2,
    this.planCards = true,
  })  : rng = Random(seed),
        evaluator = evaluator ?? HeuristicEvaluator() {
    budget = customBudget ??
        switch (level) {
          AiLevel.easy => IsmctsBudget.easy,
          AiLevel.medium => IsmctsBudget.medium,
          AiLevel.hard => IsmctsBudget.hard,
          AiLevel.insane => IsmctsBudget.insane,
        };
    _helper = AiAgent(level: subPromptLevel ?? level, seed: rng.nextInt(1 << 30));
  }

  final AiLevel level;
  final Evaluator evaluator;
  final Random rng;
  final bool isWeb;

  /// Also search the card / movement choices inside the chosen action.
  final bool planCards;

  /// Opposing turns each simulation plays after my own (a large number plays to the end).
  final int rolloutTurns;

  /// Kept for API compatibility: the search runs cooperatively on the calling isolate (a Game
  /// holds closures and cannot be sent to another isolate), yielding every few milliseconds.
  final bool useBackgroundIsolate;
  late final IsmctsBudget budget;
  late final AiAgent _helper;

  final Map<int, OpponentTracker> _trackers = {};

  // Answers the search planned for the prompts inside the action it just chose.
  Map<int, PlanStep> _plan = const {};
  int _planOrdinal = 0;

  OpponentTracker _trackerFor(int seat) => _trackers.putIfAbsent(seat, () => OpponentTracker(seat));

  /// Observes game events to update opponent card tracking and defense reactions.
  void observeEvent(GameEvent event) {
    if (event is CombatEnded) {
      final c = event.combat;
      final defPlayer = c.defender.player;
      final tracker = _trackerFor(defPlayer.seat);
      final defended = c.defender.card != null;
      tracker.recordCombatDefense(defended, c.combatDamage, defPlayer.hand.length);
    }
  }

  @override
  Future<List<int>> decide(Game game, Prompt prompt) async {
    if (prompt.ask == Ask.action) {
      _plan = const {};
      _planOrdinal = 0;
    }

    // Only whole-turn action choices with a real decision are searched (see the class comment).
    // Everything else, including a single optional choice that may be declined, is answered by
    // the helper unless the search planned a better answer for it.
    if (prompt.ask != Ask.action || prompt.choices.length < 2 || game.turnNumber == 0) {
      final answer = await _helper.decide(game, prompt);
      if (_plan.isNotEmpty && prompt.ask != Ask.action) {
        final step = _plan[_planOrdinal++];
        if (step != null && step.signature == promptSignature(prompt)) return step.answer;
      }
      return answer;
    }

    for (final p in game.players) {
      if (p != prompt.player) _trackerFor(p.seat);
    }

    final engine = IsmctsEngine(
      evaluator: evaluator,
      determinizer: Determinizer(_trackers),
      budget: budget,
      rolloutTurns: rolloutTurns,
      planCards: planCards,
      random: rng,
    );

    final List<int> choice;
    if (isWeb) {
      choice = await WebTimeSlicedIsmctsRunner.runSearch(engine: engine, rootGame: game, prompt: prompt);
    } else if (useBackgroundIsolate) {
      choice = await IsolateIsmctsRunner.runSearch(engine: engine, game: game, prompt: prompt);
    } else {
      // Headless self-play / benchmarks: run flat out.
      choice = await engine.search(game, prompt);
    }
    _plan = engine.lastPlan;
    _planOrdinal = 0;
    return choice;
  }
}
