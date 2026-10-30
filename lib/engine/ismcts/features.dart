import 'dart:math';

import '../defs.dart';
import '../game.dart';
import '../state.dart';

/// Normalized feature vector extracted from a [Game] state (version 2).
///
/// The vector describes the position from [me]'s side **at the start of my turn**: that is where
/// the self-play data is recorded (the `TurnStarted` event) and where the search evaluates (after
/// my turn and the opponent's reply). It is made of [baseLength] tactical features followed by a
/// one-hot of my hero and a one-hot of the enemy hero, because the heroes differ far too much in
/// strength for the board numbers alone to predict who wins.
class StateFeatures {
  const StateFeatures(this.values);

  final List<double> values;

  /// Bump when the layout changes; models trained on another version are rejected.
  static const int version = 3;

  static const List<String> baseNames = [
    'hero_hp_diff', // 0: (myHeroHp - enemyHeroHp) / 20
    'my_hero_hp_ratio', // 1
    'enemy_hero_hp_ratio', // 2
    'sidekick_hp_diff', // 3: (mySidekickHp - enemySidekickHp) / 15
    'my_sidekick_alive', // 4: alive sidekicks / 3
    'enemy_sidekick_alive', // 5
    'hand_diff', // 6: (myHand - enemyHand) / 7
    'my_hand_size', // 7
    'enemy_hand_size', // 8
    'deck_diff', // 9: (myDeck - enemyDeck) / 30
    'my_deck_size', // 10
    'enemy_deck_size', // 11
    'fatigue_danger_my', // 12: deck <= 2
    'fatigue_danger_enemy', // 13
    'hero_distance', // 14: shortest board path / 10
    'can_attack_enemy', // 15: heroes in reach of each other
    'enemy_can_attack_me', // 16
    'my_cards_discarded', // 17
    'enemy_cards_discarded', // 18
    'my_feints_left', // 19
    'enemy_feints_left', // 20
    'turn_number_scaled', // 21
    'my_hand_combat_power', // 22: printed values in hand / 20
    'my_hand_boost_power', // 23
    'my_attack_card_ratio', // 24
    'my_defense_card_ratio', // 25
    'multi_zone_advantage', // 26: zones of my hero's space / 3
    'ranged_matchup_advantage', // 27: +1 ranged vs melee, -1 melee vs ranged
  ];

  /// Version 3 adds these card-awareness and contact features between the base block and the
  /// hero one-hots. Version 2 models stay readable (they just lack these inputs).
  static const List<String> cardNames = [
    'my_max_attack_card', // best attack value in hand / 8
    'my_max_defense_card', // best defense value in hand / 8
    'my_attack_total', // sum of attack-capable card values / 20
    'my_defense_total', // sum of defense-capable card values / 20
    'my_scheme_cards', // schemes in hand / 7
    'my_kill_threat', // min(1, best attack / enemy hero hp)
    'my_strong_cards', // cards worth 4+ / 7
    'my_fighters_in_contact', // my fighters with an enemy in reach / 4
    'enemy_fighters_in_contact', // enemy fighters with one of mine in reach / 4
    'my_total_hp_ratio', // all my fighters' hp / max hp
    'enemy_total_hp_ratio',
    'total_cards_diff', // (my hand + deck - enemy hand - deck) / 30
  ];

  static int get baseLength => baseNames.length;

  static final Expando<Map<String, int>> _heroIndex = Expando('heroIndex');

  static Map<String, int> _indexOf(GameData data) {
    return _heroIndex[data] ??= {
      for (final (i, id) in (data.heroes.keys.toList()..sort()).indexed) id: i,
    };
  }

  /// Total feature count for a game played with [data].
  static int lengthFor(GameData data, [int v = version]) =>
      baseLength + (v >= 3 ? cardNames.length : 0) + 2 * data.heroes.length;

  /// Extracts the feature vector from the perspective of [me].
  ///
  /// [heroIndex] fixes which input slot each hero uses (a model carries its own list in
  /// `hero_ids`); without it the slots follow the sorted ids of [Game.data].
  static StateFeatures extract(Game game, Player me, [int v = version, Map<String, int>? heroIndex]) {
    final enemy = game.enemiesOf(me).firstOrNull ?? (game.players.firstWhere((p) => p != me, orElse: () => me));
    final myHero = me.heroFighter;
    final enemyHero = enemy.heroFighter;

    final myHeroHpRatio = (myHero.hp / max(1, myHero.maxHp)).clamp(0.0, 1.0);
    final enemyHeroHpRatio = (enemyHero.hp / max(1, enemyHero.maxHp)).clamp(0.0, 1.0);
    final heroHpDiff = ((myHero.hp - enemyHero.hp) / 20.0).clamp(-1.5, 1.5);

    final mySidekicks = me.fighters.where((f) => f.isSidekick && f.alive).toList();
    final enemySidekicks = enemy.fighters.where((f) => f.isSidekick && f.alive).toList();
    final mySidekickHp = mySidekicks.fold<int>(0, (sum, f) => sum + f.hp);
    final enemySidekickHp = enemySidekicks.fold<int>(0, (sum, f) => sum + f.hp);
    final sidekickHpDiff = ((mySidekickHp - enemySidekickHp) / 15.0).clamp(-1.5, 1.5);

    final handDiff = ((me.hand.length - enemy.hand.length) / 7.0).clamp(-1.0, 1.0);
    final myHandSize = (me.hand.length / 7.0).clamp(0.0, 1.5);
    final enemyHandSize = (enemy.hand.length / 7.0).clamp(0.0, 1.5);

    final deckDiff = ((me.deck.length - enemy.deck.length) / 30.0).clamp(-1.0, 1.0);
    final myDeckSize = (me.deck.length / 30.0).clamp(0.0, 1.0);
    final enemyDeckSize = (enemy.deck.length / 30.0).clamp(0.0, 1.0);

    final fatigueDangerMy = me.deck.length <= 2 ? 1.0 : 0.0;
    final fatigueDangerEnemy = enemy.deck.length <= 2 ? 1.0 : 0.0;

    double distNorm = 0.5;
    double canAttack = 0.0;
    double enemyCanAttack = 0.0;
    double multiZoneAdv = 0.33;

    if (myHero.onBoard && enemyHero.onBoard) {
      final d = game.board.distance(myHero.space!, enemyHero.space!);
      distNorm = (d / 10.0).clamp(0.0, 1.0);

      if (myHero.isRanged && game.board.sharesZone(myHero.space!, enemyHero.space!)) {
        canAttack = 1.0;
      } else if (game.board.adjacent(myHero.space!, enemyHero.space!)) {
        canAttack = 1.0;
      }

      if (enemyHero.isRanged && game.board.sharesZone(enemyHero.space!, myHero.space!)) {
        enemyCanAttack = 1.0;
      } else if (game.board.adjacent(enemyHero.space!, myHero.space!)) {
        enemyCanAttack = 1.0;
      }

      if (myHero.space! < game.board.def.spaces.length) {
        multiZoneAdv = (game.board.space(myHero.space!).zones.length / 3.0).clamp(0.0, 1.0);
      }
    }

    int countFeints(Player p) {
      final discarded = p.discard.where((c) => c.def.text.values.join(' ').toLowerCase().contains('cancel')).length;
      return max(0, 3 - discarded);
    }

    final combatPower = (me.hand.fold<int>(0, (s, c) => s + (c.def.value ?? 0)) / 20.0).clamp(0.0, 2.0);
    final boostPower = (me.hand.fold<int>(0, (s, c) => s + (c.def.boost ?? 0)) / 15.0).clamp(0.0, 2.0);
    final attackRatio = (me.hand.where((c) => c.def.canAttack).length / 7.0).clamp(0.0, 1.0);
    final defenseRatio = (me.hand.where((c) => c.def.canDefend).length / 7.0).clamp(0.0, 1.0);
    final rangedMatchup = (myHero.isRanged ? 1.0 : 0.0) - (enemyHero.isRanged ? 1.0 : 0.0);

    final heroes = heroIndex ?? _indexOf(game.data);
    final extraLen = v >= 3 ? cardNames.length : 0;
    final out = List<double>.filled(baseLength + extraLen + 2 * heroes.length, 0.0);
    final base = [
      heroHpDiff,
      myHeroHpRatio,
      enemyHeroHpRatio,
      sidekickHpDiff,
      (mySidekicks.length / 3.0).clamp(0.0, 1.0),
      (enemySidekicks.length / 3.0).clamp(0.0, 1.0),
      handDiff,
      myHandSize,
      enemyHandSize,
      deckDiff,
      myDeckSize,
      enemyDeckSize,
      fatigueDangerMy,
      fatigueDangerEnemy,
      distNorm,
      canAttack,
      enemyCanAttack,
      (me.discard.length / 30.0).clamp(0.0, 1.0),
      (enemy.discard.length / 30.0).clamp(0.0, 1.0),
      countFeints(me) / 3.0,
      countFeints(enemy) / 3.0,
      (game.turnNumber / 40.0).clamp(0.0, 1.0),
      combatPower,
      boostPower,
      attackRatio,
      defenseRatio,
      multiZoneAdv,
      rangedMatchup,
    ];
    assert(base.length == baseLength);
    out.setRange(0, base.length, base);

    if (v >= 3) {
      final atk = [for (final c in me.hand) if (c.def.canAttack) c.def.value ?? 0];
      final def = [for (final c in me.hand) if (c.def.canDefend) c.def.value ?? 0];
      final bestAtk = atk.fold<int>(0, max);
      final bestDef = def.fold<int>(0, max);

      int contact(Player a, Player b) {
        var n = 0;
        for (final f in a.onBoard) {
          if (b.onBoard.any((t) => game.inReach(f, t))) n++;
        }
        return n;
      }

      double hpRatio(Player p) {
        final cur = p.fighters.fold<int>(0, (sum, f) => sum + (f.defeated ? 0 : f.hp));
        final top = p.fighters.fold<int>(0, (sum, f) => sum + f.maxHp);
        return top == 0 ? 0.0 : cur / top;
      }

      final extra = [
        (bestAtk / 8.0).clamp(0.0, 1.5),
        (bestDef / 8.0).clamp(0.0, 1.5),
        (atk.fold<int>(0, (a, b) => a + b) / 20.0).clamp(0.0, 2.0),
        (def.fold<int>(0, (a, b) => a + b) / 20.0).clamp(0.0, 2.0),
        (me.hand.where((c) => c.def.isScheme).length / 7.0).clamp(0.0, 1.0),
        (bestAtk / max(1, enemyHero.hp)).clamp(0.0, 1.0),
        (me.hand.where((c) => (c.def.value ?? 0) >= 4).length / 7.0).clamp(0.0, 1.0),
        (contact(me, enemy) / 4.0).clamp(0.0, 1.0),
        (contact(enemy, me) / 4.0).clamp(0.0, 1.0),
        hpRatio(me).clamp(0.0, 1.0),
        hpRatio(enemy).clamp(0.0, 1.0),
        ((me.hand.length + me.deck.length - enemy.hand.length - enemy.deck.length) / 30.0).clamp(-1.0, 1.0),
      ];
      assert(extra.length == cardNames.length);
      out.setRange(baseLength, baseLength + extra.length, extra);
    }

    final mine = heroes[me.hero.id];
    final theirs = heroes[enemy.hero.id];
    final oneHot = baseLength + extraLen;
    if (mine != null) out[oneHot + mine] = 1.0;
    if (theirs != null) out[oneHot + heroes.length + theirs] = 1.0;

    return StateFeatures(out);
  }
}
