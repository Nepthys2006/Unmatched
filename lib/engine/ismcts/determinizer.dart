import 'dart:math';

import '../defs.dart';
import '../game.dart';
import '../state.dart';

/// Tracks an opponent's card history, public information, and combat reactions
/// to compute Bayesian inference weights for Information Set MCTS determinization.
class OpponentTracker {
  OpponentTracker(this.opponentSeat);

  final int opponentSeat;

  /// True if the opponent declined to defend against an attack dealing 3+ damage.
  bool declinedHighDamageDefense = false;

  /// Total number of undefended attacks received while having cards in hand.
  int undefendedCombats = 0;

  /// Publicly known cards currently in hand (e.g., revealed by effects).
  final List<CardDef> knownHand = [];

  void recordCombatDefense(bool defended, int incomingDamage, int handSize) {
    if (!defended && handSize > 0) {
      undefendedCombats++;
      if (incomingDamage >= 3) {
        declinedHighDamageDefense = true;
      }
    } else if (defended) {
      // If they just played a defense card, reset the high defense penalty
      declinedHighDamageDefense = false;
    }
  }

  void resetRound() {
    declinedHighDamageDefense = false;
  }
}

/// Information Set MCTS Determinizer.
/// Samples concrete, fully-observable game states from hidden information sets.
class Determinizer {
  Determinizer(this.trackerMap);

  final Map<int, OpponentTracker> trackerMap;

  /// Computes a determinized hand and deck for each opponent of [activePlayer].
  /// Returns `(determinizedHands, determinizedDecks)`.
  (Map<int, List<CardDef>> hands, Map<int, List<CardDef>> decks) determinize(
    Game game,
    Player activePlayer,
    Random rng,
  ) {
    final detHands = <int, List<CardDef>>{};
    final detDecks = <int, List<CardDef>>{};

    for (final p in game.players) {
      if (p == activePlayer) {
        // Active player's hand and deck are fully known to itself
        continue;
      }

      final tracker = trackerMap[p.seat];

      // 1. Calculate the exact unobserved pool of cards for player p
      // Deck composition minus discard, inPlay, removed
      final counts = <String, int>{};
      for (final c in p.hero.cards) {
        counts[c.upperTitle] = c.copies;
      }
      for (final c in p.discard) {
        counts[c.def.upperTitle] = (counts[c.def.upperTitle] ?? 1) - 1;
      }
      for (final c in p.inPlay) {
        counts[c.def.upperTitle] = (counts[c.def.upperTitle] ?? 1) - 1;
      }
      for (final c in p.removed) {
        counts[c.def.upperTitle] = (counts[c.def.upperTitle] ?? 1) - 1;
      }

      final unobservedPool = <CardDef>[];
      for (final c in p.hero.cards) {
        final rem = counts[c.upperTitle] ?? 0;
        for (var i = 0; i < rem; i++) {
          unobservedPool.add(c);
        }
      }

      // If hand is empty or unobserved pool is empty
      final handSize = min(p.hand.length, unobservedPool.length);
      if (handSize == 0) {
        detHands[p.seat] = const [];
        detDecks[p.seat] = List.of(unobservedPool)..shuffle(rng);
        continue;
      }

      // 2. Assign inference weights
      // If the opponent previously declined defense against a high-damage attack,
      // sharply reduce the probability (e.g. 0.15x) of sampling defense cards into their hand.
      final bool penalizeDefense = tracker?.declinedHighDamageDefense ?? false;

      final sampledHand = <CardDef>[];
      final remainingPool = List<CardDef>.of(unobservedPool);

      for (var k = 0; k < handSize && remainingPool.isNotEmpty; k++) {
        // Calculate cumulative sampling weights
        final weights = <double>[];
        var totalWeight = 0.0;

        for (final card in remainingPool) {
          var w = 1.0;
          if (card.canDefend && penalizeDefense) {
            // Sharply reduce probability of defense cards
            w = 0.15;
          }
          weights.add(w);
          totalWeight += w;
        }

        // Weighted random draw
        var r = rng.nextDouble() * totalWeight;
        var chosenIndex = 0;
        for (var i = 0; i < weights.length; i++) {
          r -= weights[i];
          if (r <= 0) {
            chosenIndex = i;
            break;
          }
        }

        sampledHand.add(remainingPool.removeAt(chosenIndex));
      }

      detHands[p.seat] = sampledHand;
      detDecks[p.seat] = remainingPool..shuffle(rng);
    }

    return (detHands, detDecks);
  }
}

