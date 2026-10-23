/// Decisions. Every choice a player makes goes through a [Prompt] answered by an [Agent]
/// (the UI, the AI, a test script or, later, a network peer) with the indices it picked.
library;

import 'game.dart';
import 'state.dart';

enum Ask {
  /// Turn actions; choices are [ActionChoice]s.
  action,

  /// Pick a card (hand, discard pile, revealed cards...).
  card,

  /// Pick a fighter on the board.
  fighter,

  /// Pick a space on the board.
  space,

  /// Pick one of several named options.
  option,

  /// Yes or no; choices are [true, false].
  yesNo,

  /// Pick between min and max cards.
  cards,

  /// Pick a number.
  number,

  /// Pick a path between two spaces (Shredder's Foot soldiers); choices are (int, int).
  path,
}

/// What a choice is for, so the AI can judge it without understanding the card text.
enum Intent {
  none,

  /// The chosen thing gets hurt or hindered (damage, discard, push away).
  harm,

  /// The chosen thing gets helped (heal, draw, return).
  help,

  /// Choosing where my own fighter goes.
  moveOwn,

  /// Choosing where an opposing fighter goes.
  moveEnemy,

  /// Choosing a card of mine to lose (discard, put back); pick the least useful.
  loseOwn,

  /// Choosing a card of mine to gain; pick the most useful.
  gainOwn,

  /// Choosing a card of my opponent's for them to lose; pick their best.
  loseEnemy,

  /// Choosing a card for my opponent to play (Do My Bidding); pick their worst.
  forceEnemy,
  attackCard,
  defenseCard,
  boost,
  attackTarget,
  attacker,
}

class Choice<T> {
  const Choice(this.label, this.value, {this.detail});
  final String label;
  final T value;
  final String? detail;
}

enum ActionKind { maneuver, scheme, attack }

class ActionChoice {
  const ActionChoice(this.kind, {this.card, this.fighter, this.target});
  final ActionKind kind;
  final Card? card;
  final Fighter? fighter;
  final Fighter? target;
}

class Prompt {
  Prompt({
    required this.player,
    required this.ask,
    required this.text,
    required this.choices,
    this.optional = false,
    this.skipLabel,
    this.min = 1,
    this.max = 1,
    this.intent = Intent.none,
    this.subject,
    this.source,
  });

  final Player player;
  final Ask ask;
  final String text;
  final List<Choice<Object?>> choices;

  /// The player may decline (answer with no indices).
  final bool optional;
  final String? skipLabel;
  final int min;
  final int max;
  final Intent intent;

  /// The fighter being moved/placed, or the card being resolved, when that matters.
  final Object? subject;
  final Card? source;

  @override
  String toString() => '${player.name}: $text [${choices.map((c) => c.label).join(' | ')}]${optional ? ' (optional)' : ''}';
}

abstract class Agent {
  /// Returns the indices of the chosen [Prompt.choices]; empty means skip.
  Future<List<int>> decide(Game game, Prompt prompt);
}
