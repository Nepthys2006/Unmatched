import 'dart:math';

import '../ai.dart';
import '../clone.dart';
import '../defs.dart';
import '../game.dart';
import '../prompt.dart';
import '../state.dart';
import 'determinizer.dart';
import 'evaluator.dart';

/// Thinking budget configuration for Information Set MCTS difficulty scaling.
class IsmctsBudget {
  const IsmctsBudget({
    required this.maxSimulations,
    this.timeLimit,
  });

  final int maxSimulations;
  final Duration? timeLimit;

  // Release budgets, measured on a desktop CPU (one thread): 100 sims ~0.16 s per move on
  // average, 200 sims ~0.5 s. The time limits cap the slow tail on weaker devices.
  // Easy and Medium are better served by the plain AiAgent, which is instant and makes the
  // occasional deliberate mistake; these presets exist for completeness.
  static const easy = IsmctsBudget(maxSimulations: 30);
  static const medium = IsmctsBudget(maxSimulations: 60, timeLimit: Duration(milliseconds: 1000));
  static const hard = IsmctsBudget(maxSimulations: 100, timeLimit: Duration(milliseconds: 1500));
  static const insane = IsmctsBudget(maxSimulations: 200, timeLimit: Duration(milliseconds: 2500));
}

/// A node in the Information Set MCTS search tree.
class IsmctsNode {
  IsmctsNode({
    this.action = -1,
    this.label = '',
    this.parent,
    List<int>? untriedActions,
  }) : untriedActions = untriedActions ?? [];

  final int action;
  final String label;
  final IsmctsNode? parent;
  final List<int> untriedActions;
  final Map<int, IsmctsNode> children = {};

  int visits = 0;
  double totalScore = 0.0;

  double get meanScore => visits > 0 ? totalScore / visits : 0.0;

  bool get isFullyExpanded => untriedActions.isEmpty;
  bool get isLeaf => children.isEmpty;

  /// UCT (Upper Confidence Bound for Trees) selection score.
  double uct(double explorationConstant) {
    if (visits == 0) return double.infinity;
    final parentVisits = parent?.visits ?? 1;
    return meanScore + explorationConstant * sqrt(log(parentVisits) / visits);
  }

  /// Selects the child node with the highest UCT score.
  IsmctsNode selectChild(double explorationConstant) {
    IsmctsNode? best;
    var bestScore = double.negativeInfinity;

    for (final child in children.values) {
      final score = child.uct(explorationConstant);
      if (score > bestScore) {
        bestScore = score;
        best = child;
      }
    }
    return best!;
  }
}

/// Identifies a prompt well enough to tell whether a planned answer still fits it.
String promptSignature(Prompt p) =>
    '${p.ask.name}|${p.min}-${p.max}|${p.optional ? 1 : 0}|${p.choices.map((c) => c.label).join(',')}';

/// A planned answer to the n-th prompt a player gets while carrying out one action.
class PlanStep {
  const PlanStep(this.signature, this.answer);
  final String signature;
  final List<int> answer;
}

/// What a player was asked during a simulated action, and what the default policy answered.
class PromptRecord {
  PromptRecord(this.ordinal, this.signature, this.ask, this.n, this.optional, this.min, this.max, this.answer);
  final int ordinal;
  final String signature;
  final Ask ask;
  final int n;
  final bool optional;
  final int min;
  final int max;
  final List<int> answer;

  bool get explorable => n > 1 || optional;
}

/// Plays [base]'s policy for one seat but records its prompts during one action and can force
/// chosen answers at chosen prompts, so the search can ask "what if I had played that card?".
class ScriptedAgent implements Agent {
  ScriptedAgent(this.base, this.seat);

  final AiAgent base;
  final int seat;
  final Map<int, PlanStep> overrides = {};
  final List<PromptRecord> records = [];
  bool _active = false;
  int _ordinal = 0;

  void begin() {
    _active = true;
    _ordinal = 0;
    records.clear();
  }

  void end() => _active = false;

  @override
  Future<List<int>> decide(Game game, Prompt prompt) async {
    final answer = await base.decide(game, prompt);
    if (!_active || prompt.player.seat != seat || prompt.ask == Ask.action) return answer;
    final ordinal = _ordinal++;
    final signature = promptSignature(prompt);
    records.add(PromptRecord(ordinal, signature, prompt.ask, prompt.choices.length, prompt.optional,
        prompt.min, prompt.max, answer));
    final forced = overrides[ordinal];
    return forced != null && forced.signature == signature ? forced.answer : answer;
  }
}

/// One simulated line: its evaluation and the prompts the acting player met on the way.
class _SimOutcome {
  _SimOutcome(this.reward, this.records);
  final double reward;
  final List<PromptRecord> records;
}

/// Paired score differences of one forced answer against the default.
class _Stat {
  _Stat(this.ordinal, this.step);
  final int ordinal;
  final PlanStep step;
  int n = 0;
  double sum = 0;
  double sumSq = 0;

  void add(double d) {
    n++;
    sum += d;
    sumSq += d * d;
  }

  double get mean => n == 0 ? 0 : sum / n;
  double get z {
    if (n < 2) return 0;
    final variance = max(0.0, sumSq / n - mean * mean) * n / (n - 1);
    return mean / max(sqrt(variance / n), 1e-9);
  }
}

/// Information Set Monte Carlo Tree Search over a turn's action choice.
///
/// Every simulation determinizes the hidden cards, clones the game, plays the candidate action
/// out with the real rules engine, lets a fast heuristic policy ([AiAgent]) finish the turn and
/// play [rolloutTurns] opposing turns, and scores the resulting position with [evaluator].
/// Damage, movement, card effects and eliminations are therefore all seen by the search.
class IsmctsEngine {
  IsmctsEngine({
    required this.evaluator,
    required this.determinizer,
    this.budget = IsmctsBudget.medium,
    this.pruneMargin = 0.4,
    this.minGain = 0.03,
    this.minRounds = 4,
    this.improvementZ = 1.0,
    this.rolloutTurns = 2,
    this.rolloutLevel = AiLevel.insane,
    this.planCards = true,
    this.stage1Share = 0.5,
    this.subZ = 1.5,
    this.subMinGain = 0.02,
    this.subMinRounds = 4,
    Random? random,
  }) : rng = random ?? Random();

  final Evaluator evaluator;
  final Determinizer determinizer;
  final IsmctsBudget budget;
  /// An action whose mean score trails the leader by more than this is dropped from the search.
  final double pruneMargin;

  /// An action must beat the default by this much (and by [improvementZ] standard errors, over
  /// at least [minRounds] paired rounds) before it replaces it.
  final double minGain;
  final int minRounds;
  final double improvementZ;

  /// Opposing turns simulated after the rest of my own turn. The evaluator then sees the
  /// position at the start of my next turn, which is where the training data is recorded.
  final int rolloutTurns;
  final AiLevel rolloutLevel;

  /// After choosing the action, also search the card / movement choices inside it.
  final bool planCards;

  /// Fraction of the budget spent choosing the action; the rest refines the choices inside it.
  final double stage1Share;

  /// A forced answer replaces the default only if its mean gain is [subMinGain] and [subZ]
  /// standard errors above zero over [subMinRounds] rounds. Stricter than for actions because
  /// many alternatives are tried per prompt, and the best of many noisy ones is usually luck.
  final double subZ;
  final double subMinGain;
  final int subMinRounds;
  final Random rng;

  /// The in-action answers the last [search] settled on (empty = use the default policy).
  Map<int, PlanStep> lastPlan = const {};

  /// Simulations dropped because the engine threw while playing them out (diagnostics).
  static int failedSims = 0;
  static int totalSims = 0;

  /// Searches the turn-action [prompt] (an [Ask.action] prompt of [rootGame]) and returns the
  /// chosen index. When [cooperative] is set the search yields to the event loop about every
  /// [frameBudgetMs] so a UI isolate keeps rendering.
  ///
  /// This is policy improvement over the heuristic [AiAgent]: its choice is the default, and the
  /// search only overrides it with an action that scores better under paired comparison.
  /// Each round determinizes the hidden cards once and plays every still-candidate action out
  /// under the same hidden cards and random seed (common random numbers), so
  /// `score(action) - score(default)` measures the action, not the luck of the draw. An action
  /// replaces the default only when its mean gain is [minGain] and [improvementZ] standard errors
  /// above zero; clearly worse actions are dropped early to spend the budget on the contenders.
  Future<List<int>> search(
    Game rootGame,
    Prompt prompt, {
    bool cooperative = false,
    int frameBudgetMs = 8,
  }) async {
    final n = prompt.choices.length;
    if (n == 0) return const [];
    if (n == 1) return const [0];

    final me = prompt.player;
    final defaults = await AiAgent(level: rolloutLevel, seed: rng.nextInt(1 << 30)).decide(rootGame, prompt);
    final base = defaults.isEmpty ? 0 : defaults.first;

    final root = IsmctsNode();
    for (var a = 0; a < n; a++) {
      root.children[a] = IsmctsNode(action: a, label: prompt.choices[a].label, parent: root);
    }
    // Paired differences against the default action, per candidate.
    final diffSum = List<double>.filled(n, 0);
    final diffSq = List<double>.filled(n, 0);
    final diffN = List<int>.filled(n, 0);
    var candidates = List.generate(n, (i) => i);

    lastPlan = const {};
    final total = Stopwatch()..start();
    final frame = Stopwatch()..start();
    var sims = 0;
    final share = planCards ? stage1Share : 1.0;
    final stage1Sims = max(1, (budget.maxSimulations * share).round());
    final stage1Time = budget.timeLimit == null ? null : budget.timeLimit! * share;

    for (var round = 0; sims < stage1Sims; round++) {
      if (stage1Time != null && total.elapsed >= stage1Time) break;

      final (hands, decks) = determinizer.determinize(rootGame, me, rng);
      final seed = rng.nextInt(1 << 30);
      final rewards = <int, double>{};
      for (final a in candidates) {
        if (cooperative && frame.elapsedMilliseconds >= frameBudgetMs) {
          await Future<void>.delayed(Duration.zero);
          frame.reset();
        }
        sims++;
        totalSims++;
        final reward = (await _simulate(rootGame, prompt, me, a, hands, decks, seed, const {}))?.reward;
        if (reward == null) {
          failedSims++;
          continue;
        }
        rewards[a] = reward;
        final node = root.children[a]!;
        node.visits++;
        node.totalScore += reward;
        root.visits++;
        root.totalScore += reward;
      }

      final baseReward = rewards[base];
      if (baseReward == null) continue;
      for (final e in rewards.entries) {
        if (e.key == base) continue;
        final d = e.value - baseReward;
        diffSum[e.key] += d;
        diffSq[e.key] += d * d;
        diffN[e.key]++;
      }

      // Drop actions that are clearly worse than the default.
      if (round >= 3) {
        candidates = [
          for (final a in candidates)
            if (a == base || diffN[a] < 4 || diffSum[a] / diffN[a] > -pruneMargin) a
        ];
      }
    }

    // Replace the default only with a statistically convincing improvement.
    var best = base;
    var bestGain = minGain;
    for (final a in candidates) {
      if (a == base || diffN[a] < minRounds) continue;
      final k = diffN[a];
      final mean = diffSum[a] / k;
      final variance = max(0.0, diffSq[a] / k - mean * mean) * k / max(1, k - 1);
      final se = max(sqrt(variance / k), 1e-9);
      if (mean > bestGain && mean / se >= improvementZ) {
        bestGain = mean;
        best = a;
      }
    }
    if (planCards) {
      lastPlan = await _refine(rootGame, prompt, me, best, total, sims, cooperative, frameBudgetMs);
    }
    return [best];
  }

  /// Searches the card / movement choices inside the chosen action. See [PromptRecord].
  Future<Map<int, PlanStep>> _refine(
    Game rootGame,
    Prompt prompt,
    Player me,
    int action,
    Stopwatch total,
    int simsSoFar,
    bool cooperative,
    int frameBudgetMs,
  ) async {
    final frame = Stopwatch()..start();
    var sims = simsSoFar;
    bool outOfBudget() =>
        sims >= budget.maxSimulations || (budget.timeLimit != null && total.elapsed >= budget.timeLimit!);

    Future<_SimOutcome?> run(Map<int, List<CardDef>> hands, Map<int, List<CardDef>> decks, int seed,
        Map<int, PlanStep> plan) async {
      if (cooperative && frame.elapsedMilliseconds >= frameBudgetMs) {
        await Future<void>.delayed(Duration.zero);
        frame.reset();
      }
      sims++;
      totalSims++;
      final out = await _simulate(rootGame, prompt, me, action, hands, decks, seed, plan);
      if (out == null) failedSims++;
      return out;
    }

    final stats = <String, _Stat>{};
    final options = <String, List<List<int>>>{};
    for (var round = 0; !outOfBudget(); round++) {
      final (hands, decks) = determinizer.determinize(rootGame, me, rng);
      final seed = rng.nextInt(1 << 30);
      final baseOut = await run(hands, decks, seed, const {});
      if (baseOut == null) continue;
      final prompts = baseOut.records.where((r) => r.explorable).take(4).toList();
      if (prompts.isEmpty) return const {}; // nothing to decide inside this action

      for (final rec in prompts) {
        final opts = options.putIfAbsent('${rec.ordinal}|${rec.signature}', () => _answerOptions(rec));
        for (final alt in opts) {
          if (_sameAnswer(alt, rec.answer) || outOfBudget()) continue;
          final step = PlanStep(rec.signature, alt);
          final out = await run(hands, decks, seed, {rec.ordinal: step});
          if (out == null) continue;
          final key = '${rec.ordinal}|${rec.signature}|${alt.join(',')}';
          (stats[key] ??= _Stat(rec.ordinal, step)).add(out.reward - baseOut.reward);
        }
      }
    }

    // The best convincing alternative per prompt.
    final plan = <int, PlanStep>{};
    final gain = <int, double>{};
    for (final st in stats.values) {
      if (st.n < subMinRounds || st.mean < subMinGain || st.z < subZ) continue;
      if (st.mean > (gain[st.ordinal] ?? double.negativeInfinity)) {
        gain[st.ordinal] = st.mean;
        plan[st.ordinal] = st.step;
      }
    }
    if (plan.isEmpty) return const {};

    // The picks were chosen on these same samples, so confirm the whole plan on fresh deals.
    var diffSum = 0.0;
    var k = 0;
    for (var v = 0; v < 4; v++) {
      final (hands, decks) = determinizer.determinize(rootGame, me, rng);
      final seed = rng.nextInt(1 << 30);
      final baseOut = await run(hands, decks, seed, const {});
      final planned = await run(hands, decks, seed, plan);
      if (baseOut == null || planned == null) continue;
      diffSum += planned.reward - baseOut.reward;
      k++;
    }
    return k >= 3 && diffSum / k > 0 ? plan : const {};
  }

  /// Answers worth trying for a prompt (including the default; callers skip the one in use).
  List<List<int>> _answerOptions(PromptRecord rec) {
    final out = <List<int>>[];
    if (rec.ask == Ask.cards) {
      final d = rec.answer.toList()..sort();
      out.add(d);
      for (var i = 0; i < rec.n; i++) {
        if (d.contains(i)) {
          if (d.length > rec.min) out.add([...d.where((x) => x != i)]);
          for (var j = 0; j < rec.n; j++) {
            if (!d.contains(j)) out.add([...d.where((x) => x != i), j]..sort());
          }
        } else if (d.length < rec.max) {
          out.add([...d, i]..sort());
        }
      }
    } else {
      for (var i = 0; i < rec.n; i++) {
        out.add([i]);
      }
      if (rec.optional) out.add(const []);
    }
    out.shuffle(rng);
    return out.take(9).toList();
  }

  bool _sameAnswer(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final x = a.toList()..sort();
    final y = b.toList()..sort();
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  /// Plays [action] out on a determinized clone (forcing the answers in [plan]) and returns the
  /// evaluation from [me]'s side, or null if the engine could not play the line out.
  Future<_SimOutcome?> _simulate(
    Game rootGame,
    Prompt prompt,
    Player me,
    int action,
    Map<int, List<CardDef>> hands,
    Map<int, List<CardDef>> decks,
    int seed,
    Map<int, PlanStep> plan,
  ) async {
    final scripted = ScriptedAgent(AiAgent(level: rolloutLevel, seed: seed + me.seat), me.seat)
      ..overrides.addAll(plan);
    final rollout = <Agent>[
      for (var i = 0; i < rootGame.players.length; i++)
        i == me.seat ? scripted : AiAgent(level: rolloutLevel, seed: seed + i),
    ];
    final sim = cloneGame(
      rootGame,
      agents: rollout,
      determinizedHands: hands,
      determinizedDecks: decks,
      random: Random(seed),
    );
    final p = sim.players[me.seat];
    // Nobody knows their own deck order, so the search must not either.
    p.deck.shuffle(Random(seed ^ 0x5bd1e995));

    try {
      final choice = _remap(prompt.choices[action].value as ActionChoice, sim);
      if (choice == null) return null;
      try {
        scripted.begin();
        try {
          await sim.performAction(p, choice);
        } finally {
          scripted.end();
        }
        sim.turn.actionsTaken++;
        await sim.checkWinner();
        await sim.finishTurn(p);
        for (var t = 0; t < rolloutTurns; t++) {
          await sim.playTurn(sim.nextPlayer(sim.active));
        }
      } on GameOverSignal {
        // The game ended inside the simulation; the evaluator scores the result.
      }
      return _SimOutcome(evaluator.evaluate(sim, p), List.of(scripted.records));
    } catch (_) {
      return null;
    }
  }

  /// Maps an action of the live game onto the equivalent objects of [sim] (matched by uid).
  ActionChoice? _remap(ActionChoice a, Game sim) {
    Fighter? fighter(Fighter? f) {
      if (f == null) return null;
      for (final x in sim.fighters) {
        if (x.uid == f.uid) return x;
      }
      throw StateError('fighter ${f.uid} missing from clone');
    }

    Card? card(Card? c) {
      if (c == null) return null;
      for (final x in sim.players[c.owner.seat].hand) {
        if (x.uid == c.uid) return x;
      }
      throw StateError('card ${c.uid} missing from clone');
    }

    try {
      return ActionChoice(a.kind, card: card(a.card), fighter: fighter(a.fighter), target: fighter(a.target));
    } on StateError {
      return null;
    }
  }
}
