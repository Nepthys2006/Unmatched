import 'dart:math';

import 'combat.dart';
import 'defs.dart';
import 'game.dart';
import 'prompt.dart';
import 'state.dart';

/// Creates an exact deep clone of [source] game for MCTS rollouts and determinized simulations.
Game cloneGame(
  Game source, {
  List<Agent>? agents,
  Random? random,
  Map<int, List<CardDef>>? determinizedHands,
  Map<int, List<CardDef>>? determinizedDecks,
}) {
  final rng = random ?? Random(source.rng.nextInt(1 << 30));
  
  // Create blank game
  final mapDef = source.board.def;
  final heroIds = [for (final p in source.players) p.hero.id];
  final clonedAgents = agents ?? List.of(source.agents);

  final target = Game(
    data: source.data,
    map: mapDef,
    heroIds: heroIds,
    agents: clonedAgents,
    random: rng,
  );

  // Clear pre-initialized fighters from constructor so we can deep-copy exact state
  for (final p in target.players) {
    p.fighters.clear();
  }

  // Map from old objects to new objects
  final playerMap = <Player, Player>{};
  final fighterMap = <Fighter, Fighter>{};
  final cardMap = <Card, Card>{};

  for (var i = 0; i < source.players.length; i++) {
    final sP = source.players[i];
    final tP = target.players[i];
    playerMap[sP] = tP;

    tP.team = sP.team;
    tP.eliminated = sP.eliminated;
    tP.turnsTaken = sP.turnsTaken;
    tP.startSpace = sP.startSpace;
    tP.label = sP.label;
    tP.isAI = sP.isAI;

    // Clone fighters
    for (final sF in sP.fighters) {
      final tF = Fighter(sF.uid, sF.def, tP, sF.ordinal)
        ..hp = sF.hp
        ..maxHp = sF.maxHp
        ..space = sF.space
        ..tail = sF.tail
        ..defeated = sF.defeated
        ..offBoard = sF.offBoard
        ..reserve = sF.reserve;
      tP.fighters.add(tF);
      fighterMap[sF] = tF;
    }
  }

  // Clone cards helper
  Card cloneCard(Card sC, Player owner) {
    final tC = Card(sC.uid, sC.def, sC.copy, owner, virtual: sC.virtual);
    if (sC.playedBy != null) {
      tC.playedBy = playerMap[sC.playedBy!];
    }
    cardMap[sC] = tC;
    return tC;
  }

  // Populate cards for each player
  var nextUid = 100000;
  for (var i = 0; i < source.players.length; i++) {
    final sP = source.players[i];
    final tP = target.players[i];

    // Check if determinization overrides hand
    if (determinizedHands != null && determinizedHands.containsKey(sP.seat)) {
      final defs = determinizedHands[sP.seat]!;
      for (final def in defs) {
        tP.hand.add(Card(nextUid++, def, 0, tP));
      }
    } else {
      for (final c in sP.hand) {
        tP.hand.add(cloneCard(c, tP));
      }
    }

    // Check if determinization overrides deck
    if (determinizedDecks != null && determinizedDecks.containsKey(sP.seat)) {
      final defs = determinizedDecks[sP.seat]!;
      for (final def in defs) {
        tP.deck.add(Card(nextUid++, def, 0, tP));
      }
    } else {
      for (final c in sP.deck) {
        tP.deck.add(cloneCard(c, tP));
      }
    }

    for (final c in sP.discard) {
      tP.discard.add(cloneCard(c, tP));
    }
    for (final c in sP.inPlay) {
      tP.inPlay.add(cloneCard(c, tP));
    }
    for (final c in sP.removed) {
      tP.removed.add(cloneCard(c, tP));
    }
  }

  // Board tokens
  target.board.tokens.clear();
  for (final sTok in source.board.tokens) {
    final tOwner = playerMap[sTok.owner] ?? target.players.first;
    target.board.tokens.add(Token(sTok.kind, tOwner, space: sTok.space, path: sTok.path));
  }

  // Game order
  target.order.clear();
  for (final p in source.order) {
    target.order.add(playerMap[p] ?? target.players[p.seat]);
  }

  // First player
  target.first = playerMap[source.first] ?? target.players[source.first.seat];

  // Turn info
  target.turnNumber = source.turnNumber;
  target.actions = source.actions;
  target.over = source.over;
  if (source.winner != null) {
    target.winner = playerMap[source.winner!];
  }
  target.winningTeam = source.winningTeam;

  if (source.turnNumber > 0) {
    final activeP = playerMap[source.active] ?? target.players[source.active.seat];
    target.turn = TurnInfo(activeP, source.turnNumber)
      ..maneuvers = source.turn.maneuvers
      ..attacks = source.turn.attacks
      ..schemes = source.turn.schemes
      ..actionsTaken = source.turn.actionsTaken
      ..flags.addAll(source.turn.flags);

    for (final entry in source.turn.startSpace.entries) {
      final f = fighterMap[entry.key];
      if (f != null) {
        target.turn.startSpace[f] = entry.value;
      }
    }
    for (final f in source.turn.damaged) {
      final tF = fighterMap[f];
      if (tF != null) target.turn.damaged.add(tF);
    }
    for (final f in source.turn.leftSpace) {
      final tF = fighterMap[f];
      if (tF != null) target.turn.leftSpace.add(tF);
    }
    for (final entry in source.turn.attacksBy.entries) {
      final f = fighterMap[entry.key];
      if (f != null) {
        target.turn.attacksBy[f] = entry.value;
      }
    }
    for (final c in source.turn.played) {
      final tC = cardMap[c];
      if (tC != null) target.turn.played.add(tC);
    }
  }

  // Clone active combat if mid-combat
  if (source.combat != null) {
    final sC = source.combat!;
    final attF = fighterMap[sC.attacker.fighter]!;
    final defF = fighterMap[sC.defender.fighter]!;
    final tCombat = Combat(attF, defF)
      ..phase = sC.phase
      ..combatDamage = sC.combatDamage
      ..attackValue = sC.attackValue
      ..defenseValue = sC.defenseValue
      ..attackerWon = sC.attackerWon
      ..resolved = sC.resolved
      ..flags.addAll(sC.flags);

    void copySide(Side sSrc, Side sDst) {
      if (sSrc.card != null) {
        sDst.card = cardMap[sSrc.card!] ?? cloneCard(sSrc.card!, sDst.fighter.owner);
      }
      sDst.canceled = sSrc.canceled;
      sDst.afterCanceled = sSrc.afterCanceled;
      sDst.duringCanceled = sSrc.duringCanceled;
      sDst.ignored = sSrc.ignored;
      sDst.lockPrinted = sSrc.lockPrinted;
      sDst.lockZero = sSrc.lockZero;
      sDst.printedOverride = sSrc.printedOverride;
      sDst.faceUp = sSrc.faceUp;
      sDst.ops.addAll(sSrc.ops);
      sDst.vars.addAll(sSrc.vars);
      for (final b in sSrc.boosts) {
        sDst.boosts.add(cardMap[b] ?? cloneCard(b, sDst.fighter.owner));
      }
    }

    copySide(sC.attacker, tCombat.attacker);
    copySide(sC.defender, tCombat.defender);
    target.combat = tCombat;
  }

  return target;
}
