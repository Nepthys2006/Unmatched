/// Things that happened, in order. The engine has already changed the state when it emits one;
/// the UI uses them to animate and to write the game log.
library;

import 'combat.dart';
import 'state.dart';

abstract class GameEvent {
  const GameEvent();
  String get log;
}

class LogEvent extends GameEvent {
  const LogEvent(this.log);
  @override
  final String log;
}

class TurnStarted extends GameEvent {
  const TurnStarted(this.player, this.number);
  final Player player;
  final int number;
  @override
  String get log => '— Turn $number: ${player.name} —';
}

class ActionsChanged extends GameEvent {
  const ActionsChanged(this.player, this.actions, this.gained);
  final Player player;
  final int actions;
  final int gained;
  @override
  String get log => gained > 0 ? '${player.name} gains $gained action${gained > 1 ? 's' : ''}.' : '';
}

class ActionTaken extends GameEvent {
  const ActionTaken(this.player, this.kind, this.detail);
  final Player player;
  final String kind;
  final String detail;
  @override
  String get log => '${player.name}: $kind$detail';
}

class CardsDrawn extends GameEvent {
  const CardsDrawn(this.player, this.cards);
  final Player player;
  final List<Card> cards;
  @override
  String get log => '${player.name} draws ${cards.length} card${cards.length == 1 ? '' : 's'}.';
}

class Exhausted extends GameEvent {
  const Exhausted(this.player);
  final Player player;
  @override
  String get log => "${player.name}'s deck is empty — each of their fighters takes 2 damage.";
}

enum Zone { hand, deck, discard, removed, inPlay, combat }

class CardMoved extends GameEvent {
  const CardMoved(this.card, this.from, this.to, {this.reason = '', this.reveal = true});
  final Card card;
  final Zone from;
  final Zone to;
  final String reason;
  final bool reveal;
  @override
  String get log {
    final who = card.owner.name;
    final name = reveal ? card.title : 'a card';
    return switch ((from, to)) {
      (Zone.hand, Zone.discard) => '$who discards $name$reason.',
      (Zone.deck, Zone.discard) => '$who discards $name from the top of their deck$reason.',
      (Zone.discard, Zone.hand) => '$who returns $name to their hand$reason.',
      (Zone.deck, Zone.hand) => '$who takes $name into their hand$reason.',
      (Zone.hand, Zone.deck) => '$who puts $name into their deck$reason.',
      (_, Zone.removed) => '$name is removed from the game$reason.',
      _ => '',
    };
  }
}

class Shuffled extends GameEvent {
  const Shuffled(this.player);
  final Player player;
  @override
  String get log => '${player.name} shuffles their deck.';
}

class FighterMoved extends GameEvent {
  const FighterMoved(this.fighter, this.path, {this.placed = false, this.swap = false});
  final Fighter fighter;

  /// Spaces visited, from start to end (just [from, to] when placed).
  final List<int> path;
  final bool placed;
  final bool swap;
  @override
  String get log => placed
      ? '${fighter.name} is placed in a new space.'
      : swap
          ? ''
          : '${fighter.name} moves ${path.length - 1} space${path.length == 2 ? '' : 's'}.';
}

class Swapped extends GameEvent {
  const Swapped(this.a, this.b);
  final Fighter a;
  final Fighter b;
  @override
  String get log => '${a.name} and ${b.name} swap spaces.';
}

class Damaged extends GameEvent {
  Damaged(this.fighter, this.amount, {this.combat = false}) : hpAfter = fighter.hp;
  final Fighter fighter;
  final int amount;
  final bool combat;
  final int hpAfter;
  @override
  String get log => '${fighter.name} takes $amount${combat ? ' combat' : ''} damage ($hpAfter left).';
}

class Healed extends GameEvent {
  Healed(this.fighter, this.amount) : hpAfter = fighter.hp;
  final Fighter fighter;
  final int amount;
  final int hpAfter;
  @override
  String get log => '${fighter.name} recovers $amount health ($hpAfter).';
}

class Defeated extends GameEvent {
  const Defeated(this.fighter);
  final Fighter fighter;
  @override
  String get log => '${fighter.name} is defeated!';
}

class Returned extends GameEvent {
  const Returned(this.fighter);
  final Fighter fighter;
  @override
  String get log => '${fighter.name} joins the battlefield.';
}

class CombatStarted extends GameEvent {
  const CombatStarted(this.combat);
  final Combat combat;
  @override
  String get log => '${combat.attacker.fighter.name} attacks ${combat.defender.fighter.name}!';
}

class CardsRevealed extends GameEvent {
  const CardsRevealed(this.combat);
  final Combat combat;
  @override
  String get log =>
      'Revealed: ${combat.attacker.card?.title ?? 'nothing'} vs ${combat.defender.card?.title ?? 'no defense'}.';
}

class PhaseChanged extends GameEvent {
  const PhaseChanged(this.combat, this.phase);
  final Combat combat;
  final Phase phase;
  @override
  String get log => '';
}

class EffectResolving extends GameEvent {
  const EffectResolving(this.side, this.timing, this.text);
  final Side side;
  final String timing;
  final String text;
  @override
  String get log => '${side.card?.title}: $text';
}

class Canceled extends GameEvent {
  const Canceled(this.side, {this.afterOnly = false});
  final Side side;
  final bool afterOnly;
  @override
  String get log => afterOnly
      ? 'AFTER COMBAT effects on ${side.card?.title} are canceled.'
      : 'All effects on ${side.card?.title} are canceled.';
}

class ValuesChanged extends GameEvent {
  const ValuesChanged(this.combat);
  final Combat combat;
  @override
  String get log => '';
}

class CardSwapped extends GameEvent {
  const CardSwapped(this.side, this.old);
  final Side side;
  final Card? old;
  @override
  String get log => '${side.player.name} now plays ${side.card?.title ?? 'no card'}.';
}

class CombatResolved extends GameEvent {
  const CombatResolved(this.combat);
  final Combat combat;
  @override
  String get log =>
      '${combat.attackerWon ? combat.attacker.fighter.name : combat.defender.fighter.name} won the combat (${combat.attackValue} vs ${combat.defenseValue}).';
}

class CombatEnded extends GameEvent {
  const CombatEnded(this.combat);
  final Combat combat;
  @override
  String get log => '';
}

class SchemePlayed extends GameEvent {
  const SchemePlayed(this.card, this.fighter);
  final Card card;
  final Fighter fighter;
  @override
  String get log => '${fighter.name} plays ${card.title}.';
}

class Boosted extends GameEvent {
  const Boosted(this.player, this.card, this.what, {this.blind = false});
  final Player player;
  final Card card;
  final String what;
  final bool blind;
  @override
  String get log => '${player.name} ${blind ? 'blind ' : ''}boosts $what with ${card.title} (+${card.def.boost ?? 0}).';
}

class Revealed extends GameEvent {
  const Revealed(this.player, this.cards, this.why);
  final Player player;
  final List<Card> cards;
  final String why;
  @override
  String get log => '${player.name} reveals ${cards.map((c) => c.title).join(', ')}$why.';
}

class StatusChanged extends GameEvent {
  const StatusChanged(this.player, this.text);
  final Player player;
  final String text;
  @override
  String get log => text;
}

class GameOver extends GameEvent {
  const GameOver(this.winner, this.reason);
  final Player? winner;
  final String reason;
  @override
  String get log => winner == null ? 'Draw.' : '${winner!.name} wins! $reason';
}
