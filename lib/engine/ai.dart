/// A rules-following computer opponent. It answers the same prompts a human does, judging each
/// choice with heuristics: card counting from public information (it never peeks at hidden
/// cards it hasn't legitimately seen), the odds of the opponent's hand, where each enemy can
/// strike next turn, and when a BOOST actually buys something.
///
/// Measure any change with `dart run tool/ai_arena.dart` (whole AI-vs-AI matches against a
/// frozen copy of an older AI) and watch one match with `dart run tool/ai_watch.dart`.
library;

import 'dart:math';

import 'combat.dart';
import 'defs.dart';
import 'game.dart';
import 'prompt.dart';
import 'state.dart';

/// Insane plays its best every time; the others also make careless choices (any legal one)
/// 10% (Hard), 25% (Medium) or 55% (Easy) of the time. In the arena Insane beats Hard 59%,
/// Medium 70% and Easy 87% of games.
enum AiLevel { easy, medium, hard, insane }

class AiAgent implements Agent {
  AiAgent({this.level = AiLevel.medium, int? seed}) : _rng = Random(seed);

  final AiLevel level;
  final Random _rng;

  /// Jitter / noise scaled by difficulty level:
  /// - insane: 0.0 noise (pure, deterministic optimal play)
  /// - hard: 0.12 noise (tiny variation)
  /// - medium: 0.6 noise (balanced play with occasional sub-optimal choices)
  /// - easy: 1.8 noise (casual with frequent blunders)
  double get _noise => switch (level) {
        AiLevel.easy => 1.8,
        AiLevel.medium => 0.6,
        AiLevel.hard => 0.12,
        AiLevel.insane => 0.0,
      };

  double _jitter() => _noise == 0.0 ? 0.0 : (_rng.nextDouble() - 0.5) * _noise;

  /// How often a choice is a careless one (any legal choice). Noise alone barely changed any
  /// decision: every level won 50% against Insane in the arena (tool/ai_arena.dart).
  double get _blunder => switch (level) {
        AiLevel.easy => 0.55,
        AiLevel.medium => 0.25,
        AiLevel.hard => 0.10,
        AiLevel.insane => 0.0,
      };

  @override
  Future<List<int>> decide(Game g, Prompt p) async {
    return _decide(g, p);
  }

  List<int> _decide(Game g, Prompt p) {
    final n = p.choices.length;
    if (n == 0) return const [];
    if (_blunder > 0 && const {Ask.action, Ask.card, Ask.space, Ask.fighter}.contains(p.ask) && _rng.nextDouble() < _blunder) {
      return p.optional && _rng.nextInt(n + 1) == n ? const [] : [_rng.nextInt(n)];
    }
    switch (p.ask) {
      case Ask.action:
        return [_best(n, (i) => _actionScore(g, p.player, p.choices[i].value as ActionChoice))];
      case Ask.yesNo:
        return [_pickYesNo(g, p)];
      case Ask.option:
        return [_pickOption(g, p)];
      case Ask.number:
        return [_pickNumber(g, p)];
      case Ask.cards:
        return _pickCards(g, p);
      case Ask.card:
        return _pickCard(g, p);
      case Ask.fighter:
        return _pickFighter(g, p);
      case Ask.space:
        return _pickSpace(g, p);
      case Ask.path:
        return _pickPath(g, p);
    }
  }

  int _best(int n, double Function(int i) score) {
    var best = 0;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < n; i++) {
      final s = score(i) + _jitter();
      if (s > bestScore) {
        bestScore = s;
        best = i;
      }
    }
    return best;
  }

  // ------------------------------------------------------------------------------- card counting

  _OpponentTracker _tracker(Game g, Player me, Player opponent) => _OpponentTracker(g, me, opponent);

  // ------------------------------------------------------------------------------- cards

  /// How useful a card is to keep in hand, taking living fighters and defensive needs into account.
  double worth(Card c, [Player? p]) {
    final t = c.def.text.values.join(' ').toLowerCase();
    final owner = p ?? c.owner;

    // Dead card check: if no living fighter can use this card, it can only be used to boost/discard.
    final canBeUsed = owner.alive.any((f) => owner.script.fighterMayUse(c, f));
    if (!canBeUsed) {
      return (c.def.boost ?? 0) * 0.35;
    }

    var w = (c.def.value ?? 2).toDouble() + (c.def.boost ?? 0) * 0.35;
    if (c.def.type == CardType.versatile) w += 0.8;
    if (c.def.isScheme) w += 0.9;

    // Feint (cancel effects) is one of the most critical survival cards in Unmatched.
    if (t.contains('cancel')) w += 2.0;
    if (t.contains('prevent all damage')) w += 2.5;
    if (t.contains('gain 1 action') || t.contains('gain 2 actions')) w += 1.4;
    if (t.contains('damage')) w += 1.1;

    // Near fatigue, drawing cards becomes dangerous (exhaustion deals 2 damage per draw).
    if (t.contains('draw')) {
      if (owner.deck.isEmpty) {
        w -= 3.0;
      } else if (owner.deck.length <= 2) {
        w -= 1.0;
      } else {
        w += 0.9;
      }
    }

    if (t.contains('recover')) {
      final missingHp = owner.heroFighter.maxHp - owner.heroFighter.hp;
      if (missingHp >= 3) {
        w += 1.4;
      } else if (missingHp == 0) {
        w -= 0.5;
      }
    }

    // Defensive shield necessity: do not discard your only defense card.
    if (c.def.canDefend) {
      final defCards = owner.hand
          .where((x) => x.def.canDefend && owner.alive.any((f) => owner.script.fighterMayUse(x, f)))
          .length;
      if (defCards <= 1) {
        w += 2.8;
      } else if (defCards == 2) {
        w += 1.2;
      }
    }

    return w;
  }

  double _effectBonus(Card c, {required bool attacking, Player? me}) {
    final t = c.def.text.values.join(' ').toLowerCase();
    var b = 0.0;
    if (t.contains('draw')) {
      if (me != null && me.deck.isEmpty) {
        b -= 3.0; // Avoid self-exhaustion
      } else {
        b += attacking ? 0.7 : 1.0;
      }
    }
    if (t.contains('damage')) b += attacking ? 1.4 : 0.8;
    if (t.contains('cancel')) b += attacking ? 0.8 : 2.5;
    if (t.contains('boost this')) b += 1.8;
    if (t.contains('gain 1 action')) b += attacking ? 2.2 : 0.0;
    if (t.contains('prevent all damage')) b += attacking ? 0.0 : 4.5;
    if (t.contains('move your fighter') || t.contains('place your fighter')) {
      b += attacking ? 0.8 : 2.0; // After-combat escape on defense breaks follow-up attacks
    }
    return b;
  }

  int _estimatedValue(Game g, Combat? c, Side s, Card card) {
    final old = s.card;
    s.card = card;
    final v = g.valueOf(s).total;
    s.card = old;
    return v;
  }

  List<int> _pickCard(Game g, Prompt p) {
    final cards = [for (final ch in p.choices) ch.value as Card];
    switch (p.intent) {
      case Intent.attackCard:
        return _pickAttackCard(g, p, cards);
      case Intent.defenseCard:
        return _pickDefenseCard(g, p, cards);
      case Intent.boost:
        return _pickBoostCard(g, p, cards);
      case Intent.loseOwn:
        return [_best(cards.length, (i) => -worth(cards[i], p.player))];
      case Intent.loseEnemy:
        return [_best(cards.length, (i) => worth(cards[i]))];
      case Intent.forceEnemy:
        return [_best(cards.length, (i) => -(cards[i].def.value ?? 0) - _effectBonus(cards[i], attacking: true))];
      default:
        if (p.optional && _rng.nextDouble() < 0.1) return const [];
        return [_best(cards.length, (i) => worth(cards[i], p.player))];
    }
  }

  List<int> _pickAttackCard(Game g, Prompt p, List<Card> cards) {
    final c = p.subject as Combat;
    final defPlayer = c.defender.player;
    final defFighter = c.defender.fighter;
    final defHand = defPlayer.hand.length;
    final tracker = _tracker(g, p.player, defPlayer);

    // Count how many defense cards we will have remaining in hand after this attack
    final currentDefCards = p.player.hand
        .where((x) => x.def.canDefend && p.player.alive.any((f) => p.player.script.fighterMayUse(x, f)))
        .length;

    final hasFeint = defHand > 0 && tracker.remainingFeints() > 0;
    return [
      _best(cards.length, (i) {
        final card = cards[i];
        final v = _estimatedValue(g, c, c.attacker, card);
        final cardWorth = worth(card, p.player);

        // The defender's best card is uncertain: weigh each outcome by its chance, from the
        // cards they may hold and how many they hold.
        var score = tracker.expectedDamage(defFighter, v) * 2.8 +
            tracker.killChance(defFighter, v) * _killValue(defFighter) +
            _effectBonus(card, attacking: true, me: p.player);

        // High printed values (>= 5) punch through Feint safely
        if (v >= 5 && hasFeint) score += 2.0;

        // Preserve versatile cards if we are low on defense
        if (card.def.type == CardType.versatile && currentDefCards <= 1) {
          score -= 3.5;
        }

        score -= cardWorth * 0.15;
        return score;
      })
    ];
  }

  /// What one damage to [f] is worth (1 = one damage to a healthy hero).
  double _dmgWeight(Fighter f) {
    if (!f.isHero) return 0.5;
    return f.hp <= 6 ? 1.5 : 1.0;
  }

  /// What spending [c] on a BOOST costs, in damage. Cheap: in the arena, keeping cards back
  /// (skipping defenses, saving boosts) lost more games than spending them.
  double _boostCost(Card c, Player p) => worth(c, p) * 0.19;

  /// What defeating [f] is worth: the game, if it's the last hero of its player.
  double _killValue(Fighter f) {
    if (f.isHero) return f.owner.fighters.where((x) => x.isHero && x.alive).length <= 1 ? 120.0 : 30.0;
    return 6.0 + f.maxHp;
  }

  List<int> _pickDefenseCard(Game g, Prompt p, List<Card> cards) {
    final c = p.subject as Combat;
    final attPlayer = c.attacker.player;
    final attFighter = c.attacker.fighter;
    final defFighter = c.defender.fighter;
    final tracker = _tracker(g, p.player, attPlayer);

    // Determine incoming threat
    int threat;
    int maxThreat;
    bool threatKnown = false;
    final attCard = c.attacker.card;
    if (attCard != null && (c.attacker.faceUp || p.player.script.known.contains(attCard))) {
      threat = _estimatedValue(g, c, c.attacker, attCard);
      maxThreat = threat;
      threatKnown = true;
    } else {
      threat = tracker.expectedAttack(attFighter, extra: 1).round();
      maxThreat = tracker.maxAttack(attFighter);
      // Account for modifiers like King Arthur's boost
      final extraBoost = c.attacker.ops.fold(0, (a, o) => a + (o.isSet ? 0 : o.amount));
      threat += extraBoost;
      maxThreat += extraBoost;
    }

    // Sidekick defense: if sidekick has 1 HP and cannot survive, save the card!
    if (defFighter.isSidekick && defFighter.maxHp == 1 && threat >= 2 && p.optional) {
      final canNegate = cards.any((cd) {
        final txt = cd.def.text.values.join(' ').toLowerCase();
        return txt.contains('prevent all damage') || txt.contains('cancel');
      });
      if (!canNegate) {
        return const []; // Skip defense: don't waste cards on doomed 1-HP sidekicks
      }
    }

    var bestI = -1;
    var bestS = double.negativeInfinity;
    final isHero = defFighter.isHero;
    final isLethalThreat = maxThreat >= defFighter.hp;

    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      final v = _estimatedValue(g, c, c.defender, card);
      final txt = card.def.text.values.join(' ').toLowerCase();
      final isCancel = txt.contains('cancel');
      final isPreventAll = txt.contains('prevent all damage');
      final cardWorth = worth(card, p.player);

      var s = 0.0;

      // Lethal survival priority
      if (isLethalThreat && isHero) {
        if (isPreventAll) {
          s = 200.0;
        } else if (isCancel && !threatKnown) {
          s = 180.0;
        } else if (v >= maxThreat) {
          s = 160.0 + v;
        } else if (v >= threat) {
          s = 120.0 + v;
        } else {
          s = 50.0 + v * 5.0;
        }
      } else {
        final saved = min(v, threat).toDouble();
        s = saved * 2.5 + _effectBonus(card, attacking: false, me: p.player) - cardWorth * 0.2;

        if (isCancel) {
          // Feint is especially valuable if opponent has dangerous combat effects
          s += tracker.remainingDangerousEffects(attFighter) ? 3.5 : 1.0;
        }

        // After-combat movement allows escaping the opponent's 2nd action attack
        if ((txt.contains('move your fighter') || txt.contains('place your fighter')) && g.actions > 0) {
          s += 3.5;
        }
      }

      s += _jitter();
      if (s > bestS) {
        bestS = s;
        bestI = i;
      }
    }

    // Always defend when the hit could be lethal on hero
    if (bestI < 0 && isHero && isLethalThreat) {
      bestI = _best(cards.length, (i) => (cards[i].def.value ?? 0).toDouble());
    }

    if (bestI < 0 && p.optional) return const [];
    return [max(0, bestI)];
  }

  List<int> _pickBoostCard(Game g, Prompt p, List<Card> cards) {
    final me = p.player;

    // In combat boost (e.g. King Arthur face-down attack boost, or boost in defense)
    if (p.subject is Side) {
      final s = p.subject as Side;
      if (s.isAttacker) {
        // Attack boost: only boost if needed to defeat or lethal the opponent
        final target = s.combat.defender.fighter;
        final defHand = target.owner.hand.length;
        final currentVal = g.valueOf(s).total;

        if (defHand == 0 && currentVal >= target.hp) {
          if (p.optional) return const []; // Already lethal unblocked!
        }

        // Worth it only if the extra damage (or chance to defeat) beats keeping the card.
        final tracker = _tracker(g, me, target.owner);
        double value(int v) => tracker.expectedDamage(target, v) * _dmgWeight(target) + tracker.killChance(target, v) * _killValue(target);
        double gain(int i) => value(currentVal + g.boostValueOf(cards[i])) - value(currentVal) - _boostCost(cards[i], me);
        final i = _best(cards.length, gain);
        return gain(i) > 0 || !p.optional ? [i] : const [];
      } else {
        // Defense boost: boost to prevent lethal damage
        final currentDef = g.valueOf(s).total;
        final attVal = g.valueOf(s.other).total;
        if (currentDef >= attVal && p.optional) {
          return const []; // No damage being taken anyway
        }
        return [
          _best(cards.length, (i) {
            final b = g.boostValueOf(cards[i]);
            return b * 2.5 - worth(cards[i], me);
          })
        ];
      }
    }

    // Maneuver boost: decide if boosting movement is worth a card
    if (p.optional) {
      final handLen = me.hand.length;
      final hero = me.heroFighter;
      final foes = g.enemyFighters(me).where((e) => e.onBoard).toList();

      // Boosting must buy something the normal move doesn't (boosting whenever the hand was big,
      // or to "escape" without checking the extra spaces reach safety, wasted cards).
      final most = cards.map(g.boostValueOf).fold(0, max);

      // Reach a space to attack from, keeping an attack card to attack with.
      bool canReachAttack = false;
      if (g.actions > 0 && foes.isNotEmpty) {
        for (final f in me.onBoard) {
          final attacks = me.hand.where((c) => g.canAttackWith(c, f)).toList();
          if (attacks.isEmpty || (attacks.length == 1 && cards.length == 1 && cards.single == attacks.single)) continue;
          final spots = _strikeSpots(g, f, foes);
          if (g.reachable(f, g.moveAllowance(f)).keys.any(spots.contains)) continue;
          if (g.reachable(f, g.moveAllowance(f) + most).keys.any(spots.contains)) {
            canReachAttack = true;
            break;
          }
        }
      }

      // A hurt hero ending the turn: reach a space no enemy can strike next turn.
      bool needEscape = false;
      if (g.actions == 0 && hero.onBoard && hero.hp <= 6 && foes.isNotEmpty) {
        bool safe(int s) => foes.every((e) => !_strikeZones(g, e).$2.contains(s));
        needEscape = !g.reachable(hero, g.moveAllowance(hero)).keys.any(safe) &&
            g.reachable(hero, g.moveAllowance(hero) + most).keys.any(safe);
      }

      // Overfull hand: boost to cycle cards and avoid hand limit discard
      final overflow = handLen >= 7;

      // Has dead cards (sidekick dead)
      final hasDeadCard = cards.any((c) => !me.alive.any((f) => me.script.fighterMayUse(c, f)));

      if (!canReachAttack && !needEscape && !overflow && !hasDeadCard) {
        return const []; // Conserve hand cards!
      }
    }

    // Pick the card with the highest boost-to-worth ratio, favoring dead cards
    return [
      _best(cards.length, (i) {
        final c = cards[i];
        final b = g.boostValueOf(c);
        final w = worth(c, me);
        final isDead = !me.alive.any((f) => me.script.fighterMayUse(c, f));
        return b * 1.5 - w + (isDead ? 5.0 : 0.0);
      })
    ];
  }

  List<int> _pickCards(Game g, Prompt p) {
    final cards = [for (final ch in p.choices) ch.value as Card];
    final order = List.generate(cards.length, (i) => i);
    if (p.intent == Intent.boost) {
      final cheap = order.where((i) => worth(cards[i], p.player) < 3.0).toList();
      final keep = max(0, p.player.hand.length - 2);
      return cheap.take(min(keep, p.max)).toList();
    }
    final lose = p.intent == Intent.loseOwn || p.intent == Intent.none;
    order.sort((a, b) {
      final wa = worth(cards[a], p.player);
      final wb = worth(cards[b], p.player);
      return lose ? wa.compareTo(wb) : wb.compareTo(wa);
    });
    final k = p.intent == Intent.gainOwn ? p.max : p.min;
    return order.take(max(k, p.min)).toList();
  }

  // ---------------------------------------------------------------------------- fighters

  List<int> _pickFighter(Game g, Prompt p) {
    final fs = [for (final ch in p.choices) ch.value as Fighter];
    final me = p.player;
    switch (p.intent) {
      case Intent.harm:
        final i = _best(fs.length, (i) {
          final f = fs[i];
          final enemy = f.isEnemyOf(me);
          var s = enemy ? 15.0 : -20.0;
          if (enemy) {
            // Priority: kill opposing hero, or pick off low-HP fighters
            if (f.isHero) {
              s += 5.0;
              if (f.hp <= 3) s += 12.0; // Near death
            } else {
              if (f.hp <= 2) s += 8.0; // Finish off sidekick
              if (f.maxHp >= 6) s += 4.0; // High-value sidekick (Watson/Merlin)
            }
          } else {
            // If forced to harm our own: harm disposable 1-HP sidekick first, NEVER hero
            if (f.isHero) s -= 30.0;
            if (f.isSidekick && f.maxHp == 1) s += 10.0;
          }
          return s;
        });
        if (p.optional && fs[i].isFriendOf(me)) return const [];
        return [i];
      case Intent.help:
        return [
          _best(fs.length, (i) {
            final f = fs[i];
            if (f.isEnemyOf(me)) return -50.0;
            var s = 10.0;
            s += (f.maxHp - f.hp) * 1.5;
            if (f.isHero) s += 5.0;
            return s;
          })
        ];
      case Intent.attackTarget:
        return [
          _best(fs.length, (i) {
            final f = fs[i];
            var s = f.isHero ? 5.0 : 1.0;
            if (f.hp <= 3) s += 8.0;
            s -= f.hp * 0.15;
            if (f.owner.hand.isEmpty) s += 6.0; // Defenseless target!
            return s;
          })
        ];
      default:
        return [0];
    }
  }

  // ------------------------------------------------------------------------------ spaces

  List<int> _pickSpace(Game g, Prompt p) {
    if (p.choices.first.value is Token) return [_rng.nextInt(p.choices.length)];
    final spaces = [for (final ch in p.choices) ch.value as int];
    if (p.subject is Token) {
      final t = p.subject as Token;
      final hero = t.owner.heroFighter;
      final own = t.owner.isAllyOf(p.player);
      return [
        _best(spaces.length, (i) {
          if (!hero.onBoard) return 0;
          final d = g.board.distance(spaces[i], hero.space!).toDouble();
          return own ? -d : d;
        })
      ];
    }
    final f = p.subject is Fighter ? p.subject as Fighter : null;
    if (f != null) {
      final own = f.isFriendOf(p.player);
      final i = _best(spaces.length, (i) => own ? ownSpaceScore(g, f, spaces[i]) : -enemySpaceThreat(g, f, spaces[i], p.player));
      return [i];
    }
    if (p.intent == Intent.harm) {
      return [
        _best(spaces.length, (i) {
          final s = spaces[i];
          var score = 0.0;
          final at = g.fighterAt(s);
          if (at != null) score += at.isFriendOf(p.player) ? -10.0 : 10.0;
          for (final n in g.board.neighbours(s)) {
            final o = g.fighterAt(n);
            if (o != null) score += o.isFriendOf(p.player) ? -2.0 : 3.0;
          }
          return score;
        })
      ];
    }
    return [_best(spaces.length, (i) => ownSpaceScore(g, p.player.heroFighter, spaces[i]))];
  }

  /// Tactical board evaluation for friendly fighter [f] on space [s].
  double ownSpaceScore(Game g, Fighter f, int s) {
    final foes = g.enemyFighters(f.owner).where((e) => e.onBoard).toList();
    if (foes.isEmpty) return 0.0;

    final myHero = f.owner.heroFighter;
    final usableAttacks = f.owner.hand.where((c) => g.canAttackWith(c, f)).length;
    final defCards = f.owner.hand
        .where((c) => c.def.canDefend && f.owner.alive.any((a) => f.owner.script.fighterMayUse(c, a)))
        .length;
    final actionsLeft = g.actions;

    var score = 0.0;

    for (final e in foes) {
      final d = _walk(g, s, e.space!);
      final adj = g.board.adjacent(s, e.space!);
      final sharesZone = g.board.sharesZone(s, e.space!);
      final canHit = adj || (f.isRanged && sharesZone);
      final eCanHit = adj || (e.isRanged && sharesZone);
      final weight = e.isHero ? 2.5 : 1.0;

      // 1. Attack Reach & Timing
      if (canHit && usableAttacks > 0) {
        if (actionsLeft > 0) {
          // Action 1: Being in strike range allows Action 2 attack!
          score += 7.0 * weight;
        } else {
          // Action 2 (end of turn)
          if (f.isRanged && sharesZone && !adj) {
            // Optimal Ranged Kiting: in zone to shoot, but not adjacent to be hit in melee!
            score += 8.0 * weight;
          } else if (!f.isRanged && adj) {
            if (defCards >= 2 || f.hp >= 8 || e.hp <= 3) {
              score += 5.0 * weight; // Aggressive pressure
            } else if (defCards <= 1 && f.hp <= 5) {
              score -= 3.0; // Vulnerable to counter-attack
            }
          }
        }
      }

      // 2. Kiting & Spacing Tactics
      if (f.isRanged) {
        if (adj && !e.isRanged) {
          // Melee enemy adjacent to our ranged fighter is hazardous!
          score -= 5.5;
        } else if (sharesZone && d >= 2) {
          // Sweet spot: 2+ spaces away in shared zone
          score += 6.0 * weight;
        } else if (!sharesZone) {
          // Close in towards zone range
          score -= d * 0.5;
        }
      } else {
        // Melee fighter
        if (e.isRanged) {
          if (adj) {
            score += 6.0 * weight; // Melee fighter locks ranged opponent in melee
          } else if (sharesZone) {
            score -= 2.5; // In ranged firing line without being able to hit
          } else {
            score += 1.5; // Broke line of sight
          }
        } else {
          // Melee vs Melee
          if (actionsLeft > 0) {
            score -= d * 1.2; // Move toward enemy
          } else {
            if (f.hp <= 4 || defCards <= 1) {
              // Maintain 2-space gap to prevent free double-attacks
              score += min(d, 3) * 1.2;
            } else {
              score -= d * 0.8;
            }
          }
        }
      }

      // 3. Enemy Threat
      if (eCanHit) {
        score -= (f.hp <= 5 ? 4.0 : 1.5) * (e.isHero ? 1.5 : 0.8);
      }
    }

    // 4. Ending the turn where an enemy can strike next turn: twice if they need not move.
    // (The strongest single change in the arena: 50% -> 55% against the old AI.)
    if (actionsLeft == 0) {
      final w = f.isHero ? (f.hp <= 6 ? 2.0 : 1.0) : 0.4;
      for (final e in foes) {
        if (e.owner.hand.isEmpty && e.owner.deck.isEmpty) continue;
        final (now, later) = _strikeZones(g, e);
        final hit = _tracker(g, f.owner, e.owner).expectedAttack(e, extra: 1);
        if (now.contains(s)) {
          score -= 8 * w * hit;
        } else if (later.contains(s)) {
          score -= 4 * w * hit;
        }
      }
    }

    // 5. Sidekick Meat-Shielding
    if (f.isSidekick && myHero.onBoard && f != myHero) {
      final foeHero = foes.firstWhere((e) => e.isHero, orElse: () => foes.first);
      final heroDistToFoe = g.board.distance(myHero.space!, foeHero.space!);
      final sidekickDistToFoe = g.board.distance(s, foeHero.space!);
      final sidekickDistToHero = g.board.distance(s, myHero.space!);

      if (sidekickDistToFoe < heroDistToFoe && sidekickDistToHero <= 2) {
        score += 4.0; // Body-blocking the hero!
      }

      // 1-HP minions swarm enemy hero
      if (f.maxHp == 1 && g.board.adjacent(s, foeHero.space!)) {
        score += 3.5;
      }
    }

    // 6. Zone Cover against Ranged Opponents
    if (foes.any((e) => e.isRanged)) {
      final zoneCount = g.board.zoneCount(s);
      score += (3 - zoneCount) * 0.6; // Single zone provides better cover than multi-zone
    }

    return score;
  }

  /// Spaces from which [f] could attack one of [foes].
  Set<int> _strikeSpots(Game g, Fighter f, Iterable<Fighter> foes) => {
        for (final foe in foes) ...{...g.board.neighbours(foe.space!), if (f.isRanged) ...g.board.zoneOf(foe.space!)},
      };

  static final _walks = Expando<Map<int, Map<int, int>>>();

  /// Movement needed to walk from [a] to [b], ignoring fighters: arrows only go forwards and
  /// "+1" paths cost 2.
  int _walk(Game g, int a, int b) {
    final byStart = _walks[g.board.def] ??= {};
    final dist = byStart[a] ??= () {
      final d = <int, int>{a: 0};
      final todo = [a];
      while (todo.isNotEmpty) {
        todo.sort((x, y) => d[y]!.compareTo(d[x]!));
        final s = todo.removeLast();
        for (final n in g.board.stepsFrom(s)) {
          final c = d[s]! + g.board.stepCost(s, n);
          if (c < (d[n] ?? 1 << 20)) {
            d[n] = c;
            todo.add(n);
          }
        }
      }
      return d;
    }();
    return dist[b] ?? 1 << 20;
  }

  final Map<Fighter, (int, int?, Set<int>, Set<int>)> _zones = {};

  /// Where [e] can attack from: now (without moving), and after one maneuver (its move
  /// value plus a typical BOOST, following arrows and +1 paths and blocked by fighters).
  (Set<int>, Set<int>) _strikeZones(Game g, Fighter e) {
    final key = (g.log.length, e.space);
    final cached = _zones[e];
    if (cached != null && cached.$1 == key.$1 && cached.$2 == key.$2) return (cached.$3, cached.$4);
    Set<int> from(int s) => {s, ...g.board.neighbours(s), if (e.isRanged) ...g.board.zoneOf(s)};
    final now = from(e.space!);
    final later = <int>{...now};
    final boost = e.owner.hand.isEmpty ? 0 : 1;
    for (final s in g.reachable(e, g.moveAllowance(e) + boost).keys) {
      later.addAll(from(s));
    }
    _zones[e] = (key.$1, key.$2, now, later);
    return (now, later);
  }

  /// How dangerous opposing fighter [f] would be to [me] in space [s].
  double enemySpaceThreat(Game g, Fighter f, int s, Player me) {
    var t = 0.0;
    for (final m in g.onBoard.where((m) => m.isFriendOf(me))) {
      final adj = g.board.adjacent(s, m.space!);
      final sharesZone = g.board.sharesZone(s, m.space!);
      if (adj) t += m.isHero ? 6.0 : 2.5;
      if (f.isRanged && sharesZone && !adj) t += m.isHero ? 4.5 : 1.5;
      t -= g.board.distance(s, m.space!) * 0.3;
    }
    return t;
  }

  List<int> _pickPath(Game g, Prompt p) {
    // Shredder's foot soldiers or paths: choke points near enemy hero
    final foes = g.enemyFighters(p.player).where((e) => e.onBoard).toList();
    return [
      _best(p.choices.length, (i) {
        final (a, b) = p.choices[i].value as (int, int);
        var d = 99;
        for (final e in foes) {
          d = min(d, min(g.board.distance(a, e.space!), g.board.distance(b, e.space!)));
        }
        return -d.toDouble();
      })
    ];
  }

  // ----------------------------------------------------------------------------- actions

  double _actionScore(Game g, Player me, ActionChoice a) {
    switch (a.kind) {
      case ActionKind.attack:
        final f = a.fighter!, t = a.target!;
        final cards = me.hand.where((c) => g.canAttackWith(c, f) && g.canTargetWith(c, f, t)).toList();
        if (cards.isEmpty) return -99.0;

        final tracker = _tracker(g, me, t.owner);

        // Target with 0 cards in hand is completely defenseless!
        // (Scoring with the exact odds of their best defense, as card choice does, lost games:
        // the weights below are tuned to these rougher estimates.)
        if (t.owner.hand.isEmpty) {
          var bestDmg = 0;
          for (final c in cards) {
            final v = _estimatedValue(g, null, Side(Combat(f, t), true, f), c);
            bestDmg = max(bestDmg, v);
          }
          if (bestDmg >= t.hp) {
            return t.isHero ? 150.0 : 40.0; // Lethal kill!
          }
          return bestDmg * 3.5 + 5.0 + (t.isHero ? 4.0 : 1.0);
        }
        final expDef = tracker.averageDefense(t);
        final maxDef = tracker.maxDefense(t);

        var bestScore = double.negativeInfinity;
        for (final c in cards) {
          final v = _estimatedValue(g, null, Side(Combat(f, t), true, f), c);
          final guaranteedDmg = max(0, v - maxDef);
          final expDmg = max(0.0, v - expDef);

          if (guaranteedDmg >= t.hp && t.isHero) {
            return 120.0; // Guaranteed lethal game win!
          }
          if (expDmg >= t.hp && t.isHero) {
            bestScore = max(bestScore, 80.0);
            continue;
          }

          var cardS = expDmg * 3.0 + _effectBonus(c, attacking: true, me: me);
          if (t.isHero) cardS += 3.5;
          if (c.def.type == CardType.versatile) {
            final defCount = me.hand
                .where((x) => x != c && x.def.canDefend && me.alive.any((al) => me.script.fighterMayUse(x, al)))
                .length;
            if (defCount == 0) cardS -= 2.5; // Don't leave hand defenseless
          }
          bestScore = max(bestScore, cardS);
        }

        // Small fighters penalty unless clustered
        if (t.isSmall) {
          bestScore -= 4.5 - 0.9 * g.fightersAt(t.space!).where((o) => o.isSmall && o.owner == t.owner).length;
        }

        if (g.actions > 0) bestScore += 1.5; // Action 1 attack gives tempo
        return bestScore;

      case ActionKind.scheme:
        final c = a.card!;
        final t = c.def.text.values.join(' ').toLowerCase();
        var s = 3.0;

        // Draw evaluation
        if (t.contains('draw')) {
          if (me.deck.isEmpty) {
            s -= 15.0; // Never draw into fatigue!
          } else if (me.deck.length <= 2) {
            s -= 4.0;
          } else if (me.hand.length <= 2) {
            s += 5.0;
          } else if (me.hand.length >= 6) {
            s += 0.5;
          } else {
            s += 2.5;
          }
        }

        if (t.contains('gain') && t.contains('action')) s += 4.5; // Free action / cantrip!

        // Direct damage ignores defense cards
        if (t.contains('damage')) {
          final foeHero = g.enemyFighters(me).where((e) => e.isHero && e.onBoard).firstOrNull;
          if (foeHero != null && foeHero.hp <= 3) {
            s += 12.0; // Direct lethal snipe!
          } else {
            s += 3.5;
          }
        }

        // Healing
        if (t.contains('recover')) {
          final missing = me.heroFighter.maxHp - me.heroFighter.hp;
          if (missing >= 4) {
            s += 5.0;
          } else if (missing <= 1) {
            s -= 2.0;
          }
        }

        return s;

      case ActionKind.maneuver:
        var s = 2.0;

        // FATIGUE PENALTY: drawing from an empty deck deals 2 damage to all fighters!
        if (me.deck.isEmpty) {
          return -20.0;
        }

        // Hand starvation: replenish hand
        if (me.hand.length <= 1) {
          s += 6.5;
        } else if (me.hand.length <= 3) {
          s += 3.5;
        } else if (me.hand.length >= 7 && g.actions == 0) {
          s -= 1.5; // Avoid overdrawing and discarding
        }

        final canAttackNow = g.legalActions(me).any((x) => x.kind == ActionKind.attack);
        if (!canAttackNow) {
          // If we can't attack now, maneuver on Action 1 to position for Action 2 attack
          if (g.actions > 0) {
            final foes = g.enemyFighters(me).where((e) => e.onBoard).toList();
            bool canReach = false;
            for (final f in me.onBoard) {
              if (me.hand.where((c) => g.canAttackWith(c, f)).isEmpty) continue;
              // Somewhere this fighter can actually move to (ranged: in a shared zone).
              canReach = _strikeSpots(g, f, foes).any(g.reachable(f, g.moveAllowance(f)).containsKey);
              if (canReach) break;
            }
            if (canReach) s += 6.0; // Maneuver and Strike!
          }
        } else {
          // If we can attack now, prefer attacking unless low HP
          s -= 1.0;
        }

        // Stalling when opponent deck is empty
        final opp = g.players.where((o) => o.isEnemyOf(me) && !o.defeated).firstOrNull;
        if (opp != null && opp.deck.isEmpty) s += 4.0;

        return s;
    }
  }

  // ------------------------------------------------------------------------------ yes/no & options

  int _pickYesNo(Game g, Prompt p) {
    final text = p.text.toLowerCase();

    // Blind boost decisions
    if (text.contains('blind boost')) {
      if (p.player.deck.isEmpty) return 1; // No: avoid fatigue
      if (p.subject is Side) {
        final s = p.subject as Side;
        if (s.isAttacker) {
          final defFighter = s.combat.defender.fighter;
          final cur = g.valueOf(s).total;
          if (cur >= defFighter.hp && defFighter.owner.hand.isEmpty) return 1; // Already lethal
          return 0; // Yes: boost attack
        } else {
          final curDef = g.valueOf(s).total;
          final attVal = g.valueOf(s.other).total;
          if (curDef >= attVal) return 1; // Already safe
          return 0; // Yes: try to survive
        }
      }
      return p.player.deck.length > 3 ? 0 : 1;
    }

    // Damage-taking decisions
    if (text.contains('damage')) {
      final hero = p.player.heroFighter;
      return hero.hp >= 6 ? 0 : 1;
    }

    // Draw decisions
    if (text.contains('draw')) {
      return p.player.deck.isNotEmpty ? 0 : 1;
    }

    // Discarding to hinder opponent
    if (text.contains('discard') && p.intent == Intent.harm) {
      final hasDeadCard = p.player.hand.any((c) => !p.player.alive.any((f) => p.player.script.fighterMayUse(c, f)));
      if (hasDeadCard || p.player.hand.length >= 5) return 0; // Yes: discard cheap card to hinder
      return 1;
    }

    return switch (p.intent) {
      Intent.harm => 1,
      Intent.help => 0,
      Intent.none => 0,
      _ => 0,
    };
  }

  int _pickOption(Game g, Prompt p) {
    return _best(p.choices.length, (i) {
      final label = p.choices[i].label.toLowerCase();
      var s = 0.0;
      if (label.contains('damage') || label.contains('attack')) {
        final foeHero = g.enemyFighters(p.player).where((e) => e.isHero && e.onBoard).firstOrNull;
        s += (foeHero != null && foeHero.hp <= 3) ? 15.0 : 6.0;
      }
      if (label.contains('recover') || label.contains('heal')) {
        final missing = p.player.heroFighter.maxHp - p.player.heroFighter.hp;
        s += missing >= 4 ? 12.0 : 1.0;
      }
      if (label.contains('draw')) {
        s += p.player.deck.isEmpty ? -10.0 : (p.player.hand.length <= 3 ? 8.0 : 2.0);
      }
      if (label.contains('action')) s += 7.0;
      if (label.contains('move') || label.contains('place')) s += 4.0;
      return s;
    });
  }

  int _pickNumber(Game g, Prompt p) {
    if (p.intent == Intent.harm) return 0; // Min value for harmful number
    return p.choices.length - 1; // Max value for beneficial number
  }
}

/// Rule-compliant card counter that tracks public information of an opponent.
class _OpponentTracker {
  _OpponentTracker(this.game, this.me, this.opponent);
  final Game game;
  final Player me;
  final Player opponent;

  late final List<CardDef> _remaining = _calcRemaining();

  List<CardDef> _calcRemaining() {
    final counts = <String, int>{};
    for (final c in opponent.hero.cards) {
      counts[c.upperTitle] = c.copies;
    }
    for (final c in opponent.discard) {
      counts[c.def.upperTitle] = (counts[c.def.upperTitle] ?? 1) - 1;
    }
    for (final c in opponent.inPlay) {
      counts[c.def.upperTitle] = (counts[c.def.upperTitle] ?? 1) - 1;
    }
    for (final c in opponent.removed) {
      counts[c.def.upperTitle] = (counts[c.def.upperTitle] ?? 1) - 1;
    }

    final list = <CardDef>[];
    for (final c in opponent.hero.cards) {
      final rem = counts[c.upperTitle] ?? 0;
      for (var i = 0; i < rem; i++) {
        list.add(c);
      }
    }
    return list;
  }

  int remainingFeints() {
    var count = 0;
    for (final c in _remaining) {
      if (c.text.values.join(' ').toLowerCase().contains('cancel')) count++;
    }
    return count;
  }

  bool remainingDangerousEffects(Fighter f) {
    for (final c in _remaining) {
      if (!c.canAttack && !c.canDefend) continue;
      if (!c.isAny && !c.fighters.contains(f.id) && c.fighters.isNotEmpty) continue;
      final t = c.text.values.join(' ').toLowerCase();
      if (t.contains('deal') && t.contains('damage')) return true;
      if (t.contains('prevent all damage')) return true;
    }
    return false;
  }

  List<CardDef> defenseOptionsFor(Fighter f) {
    return _remaining.where((c) {
      if (!c.canDefend) return false;
      return c.isAny || c.fighters.contains(f.id) || c.fighters.isEmpty;
    }).toList();
  }

  List<CardDef> attackOptionsFor(Fighter f) {
    return _remaining.where((c) {
      if (!c.canAttack) return false;
      return c.isAny || c.fighters.contains(f.id) || c.fighters.isEmpty;
    }).toList();
  }

  /// Cards that may be in the opponent's hand: their deck and hand, as far as [me] can tell.
  int get _pool => _remaining.length;

  /// Chance that [h] cards drawn from [n] hold none of [k] particular ones.
  static double noneOf(int n, int k, int h) {
    if (k <= 0 || h <= 0) return 1;
    if (n - k < h) return 0;
    var p = 1.0;
    for (var i = 0; i < h; i++) {
      p *= (n - k - i) / (n - i);
    }
    return p;
  }

  static bool _stopsAll(CardDef c) => c.text.values.any((t) => t.toLowerCase().contains('prevent all damage'));

  /// Chance that [f]'s best defense (0 without one) is at most [x], from the opponent's hand.
  double defenseAtMost(Fighter f, int x) {
    if (x < 0) return 0;
    final k = defenseOptionsFor(f).where((c) => (c.value ?? 0) > x || _stopsAll(c)).length;
    return noneOf(_pool, k, min(opponent.hand.length, _pool));
  }

  /// Expected damage an attack worth [attack] deals to [f] if they defend with their best card.
  double expectedDamage(Fighter f, int attack) {
    var e = 0.0;
    for (var d = 1; d <= attack; d++) {
      e += defenseAtMost(f, attack - d);
    }
    return e;
  }

  /// Chance an attack worth [attack] defeats [f].
  double killChance(Fighter f, int attack) => attack < f.hp ? 0 : defenseAtMost(f, attack - f.hp);

  /// The average value of the defense cards [f] may still get (ignoring hand size).
  double averageDefense(Fighter f) {
    final defs = defenseOptionsFor(f);
    if (defs.isEmpty) return 0.0;
    return defs.fold<int>(0, (sum, c) => sum + (c.value ?? 0)) / defs.length;
  }

  int maxDefense(Fighter f) {
    if (opponent.hand.isEmpty) return 0;
    final defs = defenseOptionsFor(f);
    if (defs.isEmpty) return 0;
    return defs.map((c) => c.value ?? 0).fold(0, max);
  }

  /// The attack value [f] can expect: the best of [extra] more cards than the opponent holds
  /// (1 for a card already played face down).
  double expectedAttack(Fighter f, {int extra = 0}) {
    final atts = attackOptionsFor(f);
    if (atts.isEmpty) return 3.0;
    final h = min(opponent.hand.length + extra, _pool);
    if (h <= 0) return 0;
    final top = atts.map((c) => c.value ?? 0).fold(0, max);
    var e = 0.0;
    for (var v = 1; v <= top; v++) {
      e += 1 - noneOf(_pool, atts.where((c) => (c.value ?? 0) >= v).length, h);
    }
    return e;
  }

  int maxAttack(Fighter f) {
    final atts = attackOptionsFor(f);
    if (atts.isEmpty) return 4;
    return atts.map((c) => c.value ?? 0).fold(0, max);
  }
}

/// Picks uniformly among legal choices. Used by the fuzz tests to reach odd corners.
class RandomAgent implements Agent {
  RandomAgent([int? seed]) : _rng = Random(seed);
  final Random _rng;

  @override
  Future<List<int>> decide(Game g, Prompt p) async {
    final n = p.choices.length;
    if (n == 0) return const [];
    if (p.ask == Ask.cards) {
      final k = p.min + _rng.nextInt(p.max - p.min + 1);
      return (List.generate(n, (i) => i)..shuffle(_rng)).take(k).toList();
    }
    if (p.optional && _rng.nextInt(4) == 0) return const [];
    return [_rng.nextInt(n)];
  }
}
