import 'dart:convert';
import 'dart:math';

import '../game.dart';
import '../state.dart';
import 'features.dart';

/// Pluggable evaluator interface for Information Set MCTS.
/// Computes a win-probability/utility score in [-1.0, +1.0] from the perspective of [evaluatingPlayer].
abstract class Evaluator {
  double evaluate(Game game, Player evaluatingPlayer);
}

/// Hand-tuned parameter weights for [HeuristicEvaluator].
class HeuristicWeights {
  HeuristicWeights({
    this.heroHpWeight = 10.0,
    this.sidekickHpWeight = 2.5,
    this.handAdvantageWeight = 2.0,
    this.deckAdvantageWeight = 1.0,
    this.fatiguePenaltyWeight = 4.0,
    this.threatRangeBonus = 1.5,
    this.boardControlWeight = 1.0,
  });

  factory HeuristicWeights.fromJson(Map<String, dynamic> json) => HeuristicWeights(
        heroHpWeight: (json['heroHpWeight'] as num?)?.toDouble() ?? 10.0,
        sidekickHpWeight: (json['sidekickHpWeight'] as num?)?.toDouble() ?? 2.5,
        handAdvantageWeight: (json['handAdvantageWeight'] as num?)?.toDouble() ?? 2.0,
        deckAdvantageWeight: (json['deckAdvantageWeight'] as num?)?.toDouble() ?? 1.0,
        fatiguePenaltyWeight: (json['fatiguePenaltyWeight'] as num?)?.toDouble() ?? 4.0,
        threatRangeBonus: (json['threatRangeBonus'] as num?)?.toDouble() ?? 1.5,
        boardControlWeight: (json['boardControlWeight'] as num?)?.toDouble() ?? 1.0,
      );

  double heroHpWeight;
  double sidekickHpWeight;
  double handAdvantageWeight;
  double deckAdvantageWeight;
  double fatiguePenaltyWeight;
  double threatRangeBonus;
  double boardControlWeight;

  Map<String, dynamic> toJson() => {
        'heroHpWeight': heroHpWeight,
        'sidekickHpWeight': sidekickHpWeight,
        'handAdvantageWeight': handAdvantageWeight,
        'deckAdvantageWeight': deckAdvantageWeight,
        'fatiguePenaltyWeight': fatiguePenaltyWeight,
        'threatRangeBonus': threatRangeBonus,
        'boardControlWeight': boardControlWeight,
      };

  HeuristicWeights clone() => HeuristicWeights.fromJson(toJson());

  /// Mutates weights using Gaussian noise for evolutionary tournament tuning.
  void mutate(Random rng, {double stdDev = 0.25}) {
    double sample(double current, double minVal) {
      // Box-Muller transform for gaussian sampling
      final u1 = max(1e-7, rng.nextDouble());
      final u2 = rng.nextDouble();
      final z = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
      final next = current + z * stdDev;
      return max(minVal, next);
    }

    heroHpWeight = sample(heroHpWeight, 2.0);
    sidekickHpWeight = sample(sidekickHpWeight, 0.5);
    handAdvantageWeight = sample(handAdvantageWeight, 0.2);
    deckAdvantageWeight = sample(deckAdvantageWeight, 0.1);
    fatiguePenaltyWeight = sample(fatiguePenaltyWeight, 1.0);
    threatRangeBonus = sample(threatRangeBonus, 0.2);
    boardControlWeight = sample(boardControlWeight, 0.2);
  }
}

/// Baseline tactical evaluation heuristic for ISMCTS early-stopping.
class HeuristicEvaluator implements Evaluator {
  HeuristicEvaluator([HeuristicWeights? weights]) : weights = weights ?? HeuristicWeights();

  final HeuristicWeights weights;

  @override
  double evaluate(Game game, Player evaluatingPlayer) {
    if (game.over) {
      if (game.winner == evaluatingPlayer || (game.winningTeam != null && game.winningTeam == evaluatingPlayer.team)) {
        return 1.0;
      }
      return -1.0;
    }

    final enemy = game.enemiesOf(evaluatingPlayer).firstOrNull ??
        game.players.firstWhere((p) => p != evaluatingPlayer, orElse: () => evaluatingPlayer);

    final myHero = evaluatingPlayer.heroFighter;
    final enemyHero = enemy.heroFighter;

    // Terminal loss checks
    if (myHero.defeated) return -1.0;
    if (enemyHero.defeated) return 1.0;

    // 1. Hero HP differential (dominant weight)
    final heroHpScore = (myHero.hp - enemyHero.hp) * weights.heroHpWeight;

    // 2. Sidekick HP differential
    final mySidekickHp = evaluatingPlayer.fighters.where((f) => f.isSidekick && f.alive).fold<int>(0, (s, f) => s + f.hp);
    final enemySidekickHp = enemy.fighters.where((f) => f.isSidekick && f.alive).fold<int>(0, (s, f) => s + f.hp);
    final sidekickScore = (mySidekickHp - enemySidekickHp) * weights.sidekickHpWeight;

    // 3. Hand size advantage
    final handScore = (evaluatingPlayer.hand.length - enemy.hand.length) * weights.handAdvantageWeight;

    // 4. Deck fatigue penalty
    var fatigueScore = (evaluatingPlayer.deck.length - enemy.deck.length) * weights.deckAdvantageWeight;
    if (evaluatingPlayer.deck.isEmpty) fatigueScore -= weights.fatiguePenaltyWeight * 2;
    if (enemy.deck.isEmpty) fatigueScore += weights.fatiguePenaltyWeight * 2;

    // 5. Board positioning & threat
    var positioningScore = 0.0;
    if (myHero.onBoard && enemyHero.onBoard) {
      final inMyRange = (myHero.isRanged && game.board.sharesZone(myHero.space!, enemyHero.space!)) ||
          game.board.adjacent(myHero.space!, enemyHero.space!);
      if (inMyRange) positioningScore += weights.threatRangeBonus;

      final inEnemyRange = (enemyHero.isRanged && game.board.sharesZone(enemyHero.space!, myHero.space!)) ||
          game.board.adjacent(enemyHero.space!, myHero.space!);
      if (inEnemyRange) positioningScore -= weights.threatRangeBonus;
    }

    final total = heroHpScore + sidekickScore + handScore + fatigueScore + positioningScore;
    // S-curve squash into [-1.0, 1.0]
    return (2.0 / (1.0 + exp(-total / 25.0))) - 1.0;
  }
}

/// Learned Model Evaluator: Fast pure-Dart inference loading exported weights from local training.
/// Supports both:
/// 1. Logistic Regression: P(win) = sigmoid(w^T * x + b)
/// 2. Multi-Layer Perceptron (MLP): input -> hidden1 (ReLU) -> hidden2 (ReLU) -> output (sigmoid)
class LearnedEvaluator implements Evaluator {
  LearnedEvaluator._({
    required this.modelType,
    required this.featureVersion,
    required this.heroIndex,
    required this.mean,
    required this.std,
    this.linearWeights,
    this.linearBias,
    this.mlpW1,
    this.mlpB1,
    this.mlpW2,
    this.mlpB2,
    this.mlpW3,
    this.mlpB3,
    this.mlpWOut,
    this.mlpBOut,
  });

  final String modelType; // 'logistic' or 'mlp'

  /// [StateFeatures.version] the model was trained on.
  final int featureVersion;

  /// Input slot of each hero, from the model's `hero_ids` (null = sorted ids of the game's data).
  final Map<String, int>? heroIndex;
  final List<double> mean;
  final List<double> std;

  // Linear / Logistic
  final List<double>? linearWeights;
  final double? linearBias;

  // MLP Layers
  final List<List<double>>? mlpW1;
  final List<double>? mlpB1;
  final List<List<double>>? mlpW2;
  final List<double>? mlpB2;
  final List<List<double>>? mlpW3;
  final List<double>? mlpB3;
  final List<double>? mlpWOut;
  final double? mlpBOut;

  factory LearnedEvaluator.fromJson(Map<String, dynamic> json) {
    final type = (json['model_type'] as String?) ?? 'logistic';
    final version = (json['feature_version'] as num?)?.toInt() ?? 1;
    final ids = json['hero_ids'] as List?;
    final heroIndex = ids == null ? null : {for (final (i, id) in ids.indexed) id as String: i};
    final meanList = [for (final x in json['mean'] as List) (x as num).toDouble()];
    final stdList = [for (final x in json['std'] as List) max(1e-6, (x as num).toDouble())];

    if (type == 'mlp') {
      final w1 = [
        for (final row in json['w1'] as List) [for (final x in row as List) (x as num).toDouble()]
      ];
      final b1 = [for (final x in json['b1'] as List) (x as num).toDouble()];

      final w2 = [
        for (final row in json['w2'] as List) [for (final x in row as List) (x as num).toDouble()]
      ];
      final b2 = [for (final x in json['b2'] as List) (x as num).toDouble()];

      List<List<double>>? w3;
      List<double>? b3;
      if (json['w3'] != null && json['b3'] != null) {
        w3 = [
          for (final row in json['w3'] as List) [for (final x in row as List) (x as num).toDouble()]
        ];
        b3 = [for (final x in json['b3'] as List) (x as num).toDouble()];
      }

      final wOut = [for (final x in json['w_out'] as List) (x as num).toDouble()];
      final bOut = (json['b_out'] as num).toDouble();

      return LearnedEvaluator._(
        modelType: 'mlp',
        featureVersion: version,
        heroIndex: heroIndex,
        mean: meanList,
        std: stdList,
        mlpW1: w1,
        mlpB1: b1,
        mlpW2: w2,
        mlpB2: b2,
        mlpW3: w3,
        mlpB3: b3,
        mlpWOut: wOut,
        mlpBOut: bOut,
      );
    } else {
      final weights = [for (final x in json['weights'] as List) (x as num).toDouble()];
      final bias = (json['bias'] as num).toDouble();
      return LearnedEvaluator._(
        modelType: 'logistic',
        featureVersion: version,
        heroIndex: heroIndex,
        mean: meanList,
        std: stdList,
        linearWeights: weights,
        linearBias: bias,
      );
    }
  }

  factory LearnedEvaluator.fromString(String jsonString) =>
      LearnedEvaluator.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  double _sigmoid(double z) => 1.0 / (1.0 + exp(-z.clamp(-30.0, 30.0)));
  double _relu(double z) => z > 0 ? z : 0.0;

  @override
  double evaluate(Game game, Player evaluatingPlayer) {
    if (game.over) {
      if (game.winner == evaluatingPlayer || (game.winningTeam != null && game.winningTeam == evaluatingPlayer.team)) {
        return 1.0;
      }
      return -1.0;
    }

    final enemy = game.enemiesOf(evaluatingPlayer).firstOrNull ??
        game.players.firstWhere((p) => p != evaluatingPlayer, orElse: () => evaluatingPlayer);
    final myHero = evaluatingPlayer.heroFighter;
    final enemyHero = enemy.heroFighter;

    // Terminal anchors
    if (myHero.defeated) return -1.0;
    if (enemyHero.defeated) return 1.0;

    final rawFeatures = StateFeatures.extract(game, evaluatingPlayer, featureVersion, heroIndex).values;
    if (featureVersion < 2 || featureVersion > StateFeatures.version || mean.length != rawFeatures.length) {
      throw StateError('Model expects feature version $featureVersion with ${mean.length} inputs; '
          'this build produces ${rawFeatures.length} for that version (current is ${StateFeatures.version}). Retrain it.');
    }

    // Normalize features: z = (x - mean) / std
    final norm = List<double>.generate(rawFeatures.length, (i) {
      final m = i < mean.length ? mean[i] : 0.0;
      final s = i < std.length ? std[i] : 1.0;
      return (rawFeatures[i] - m) / s;
    });

    double winProb = 0.5;

    if (modelType == 'mlp' && mlpW1 != null && mlpW2 != null && mlpWOut != null) {
      // Layer 1: h1 = ReLU(W1 * x + b1)
      final h1 = List<double>.generate(mlpB1!.length, (j) {
        var sum = mlpB1![j];
        for (var i = 0; i < norm.length && i < mlpW1![j].length; i++) {
          sum += mlpW1![j][i] * norm[i];
        }
        return _relu(sum);
      });

      // Layer 2: h2 = ReLU(W2 * h1 + b2)
      final h2 = List<double>.generate(mlpB2!.length, (j) {
        var sum = mlpB2![j];
        for (var i = 0; i < h1.length && i < mlpW2![j].length; i++) {
          sum += mlpW2![j][i] * h1[i];
        }
        return _relu(sum);
      });

      // Layer 3 (Optional): h3 = ReLU(W3 * h2 + b3)
      final List<double> finalH;
      if (mlpW3 != null && mlpB3 != null) {
        finalH = List<double>.generate(mlpB3!.length, (k) {
          var sum = mlpB3![k];
          for (var j = 0; j < h2.length && j < mlpW3![k].length; j++) {
            sum += mlpW3![k][j] * h2[j];
          }
          return _relu(sum);
        });
      } else {
        finalH = h2;
      }

      // Output: winProb = Sigmoid(W_out * finalH + b_out)
      var outSum = mlpBOut!;
      for (var j = 0; j < finalH.length && j < mlpWOut!.length; j++) {
        outSum += mlpWOut![j] * finalH[j];
      }
      winProb = _sigmoid(outSum);
    } else if (linearWeights != null && linearBias != null) {
      // Logistic Regression forward pass
      var z = linearBias!;
      for (var i = 0; i < norm.length && i < linearWeights!.length; i++) {
        z += linearWeights![i] * norm[i];
      }
      winProb = _sigmoid(z);
    }

    // Convert probability [0.0, 1.0] to MCTS evaluation range [-1.0, +1.0]
    return (winProb * 2.0) - 1.0;
  }
}

