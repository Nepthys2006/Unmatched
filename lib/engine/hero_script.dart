/// How heroes, cards and ongoing effects plug into the rules.
///
/// * [Mod] is anything that changes the rules while it is active: a hero's special ability, an
///   ongoing scheme, a "for the rest of the turn" effect. The engine asks every active mod at each
///   hook.
/// * [CardScript] holds a card's effects by timing, written as async functions over [Fx].
/// * [HeroScript] is a hero's special ability (it is itself a [Mod]) plus the scripts for the
///   hero's cards and any setup the hero needs.
library;

import 'combat.dart';
import 'defs.dart';
import 'events.dart';
import 'game.dart';
import 'open_cards.dart';
import 'prompt.dart';
import 'state.dart';

class DamageInfo {
  const DamageInfo({this.source, this.combat = false, this.exhaustion = false, this.card, this.by});

  /// The fighter dealing the damage, if any.
  final Fighter? source;
  final bool combat;
  final bool exhaustion;
  final Card? card;

  /// The player whose effect deals the damage.
  final Player? by;
}

abstract class Mod {
  /// Shown on the HUD for ongoing effects.
  String get label => '';

  Future<void> startOfTurn(Game g, Player active) async {}
  Future<void> endOfTurn(Game g, Player active) async {}

  /// Static value changes applied after the card's own changes (Alice's size, Achilles' rage...).
  Iterable<ValueOp> valueOps(Game g, Side s) => const [];
  int moveValue(Game g, Fighter f, int v) => v;

  /// A value the card is fixed at and that can't be changed (Three Wishes: "your cards' values
  /// are 4"). Null when this mod doesn't fix it.
  int? fixedValue(Game g, Side s) => null;

  /// Extra movement granted only when maneuvering (Sinbad's voyages).
  int maneuverBonus(Game g, Fighter f) => 0;
  int boostValue(Game g, Card c, int v) => v;

  /// Cards drawn by a maneuver (Hamlet's TO BE draws one more).
  int maneuverDraws(Game g, Player p, int n) => n;
  int handLimit(Game g, Player p, int v) => v;
  bool canGainActions(Game g, Player p) => true;

  /// Returns the damage after prevention or reduction.
  int modifyDamage(Game g, Fighter target, int amount, DamageInfo info) => amount;

  /// Damage can't take [f] below this ("cannot reduce Annie's health below 1").
  int minHealth(Game g, Fighter f) => 0;
  Future<void> onDamaged(Game g, Fighter f, int amount, DamageInfo info) async {}
  Future<void> onDefeated(Game g, Fighter f) async {}
  bool cannotLeave(Game g, Fighter f) => false;

  /// [f] may move through opposing fighters (Glamour of Invisibility).
  bool movesThroughEnemies(Game g, Fighter f) => false;

  /// During a maneuver, after the boost and before any fighter moves (Glamour of Love).
  Future<void> beforeManeuverMoves(Game g, Player p) async {}

  /// An attack was just declared, before either card is played (Glamour of Jealousy).
  Future<void> onAttacked(Game g, Combat c) async {}

  /// Extra spaces [f] may step to from [from] (Invisible Man between fog tokens).
  Iterable<int> extraSteps(Game g, Fighter f, int from) => const [];

  /// Extra attack targets beyond the normal melee/ranged reach.
  bool canAlsoTarget(Game g, Fighter attacker, Fighter target) => false;
  bool uncancelable(Game g, Side s) => false;

  /// Resolves after both cards' IMMEDIATELY effects (abilities with an IMMEDIATELY timing).
  Future<void> combatImmediately(Game g, Combat c) async {}

  /// Other game effects after the cards' AFTER COMBAT effects (hero abilities).
  Future<void> afterCombat(Game g, Combat c) async {}
  Future<void> afterManeuver(Game g, Player p) async {}

  /// After a whole attack or scheme action.
  Future<void> afterAction(Game g, Player p, ActionKind kind, {Card? card, Fighter? fighter}) async {}
  bool mayIgnoreDiscard(Game g, Player p) => false;
  Future<bool> blocksHandLook(Game g, Player target, Player viewer) async => false;

  /// A card left [c.owner]'s hand as a discard. [byOpponent] when an opponent's effect caused it.
  Future<void> onDiscardedFromHand(Game g, Card c, {required bool byOpponent, Player? holder}) async {}

  /// [f] finished moving along [path] (normal movement, not placement).
  Future<void> afterMove(Game g, Fighter f, List<int> path) async {}

  /// A DURING COMBAT ability, resolved before the cards' DURING COMBAT effects (Daredevil).
  Future<void> duringCombat(Game g, Combat c) async {}

  /// [f] is about to be defeated; true keeps it from being defeated (Elektra's first death).
  Future<bool> preventDefeat(Game g, Fighter f) async => false;

  /// False stops [p] drawing cards (Right in the Face!).
  bool canDraw(Game g, Player p) => true;

  /// The attack card is chosen and the defender is about to pick theirs (Spidey-Sense).
  Future<void> beforeDefense(Game g, Combat c) async {}

  /// Where a move along [path] must stop early, as an index into [path] (Muldoon's traps), or
  /// null to let it finish.
  int? stopMove(Game g, Fighter f, List<int> path) => null;

  /// [f] arrived in [space] by moving, being placed or swapping (traps go off).
  Future<void> entered(Game g, Fighter f, int space) async {}

  /// [f] changed spaces along [path] (moving), or from path.first to path.last (placed, swapped).
  Future<void> relocated(Game g, Fighter f, List<int> path) async {}
}

/// A mod that lasts until the end of the current turn.
class TurnMod extends Mod {
  TurnMod({
    this.name = '',
    this.cannotLeaveFn,
    this.valueOpsFn,
    this.minHealthFn,
    this.modifyDamageFn,
  });
  final String name;
  final bool Function(Game g, Fighter f)? cannotLeaveFn;
  final Iterable<ValueOp> Function(Game g, Side s)? valueOpsFn;
  final int Function(Game g, Fighter f)? minHealthFn;
  final int Function(Game g, Fighter f, int amount, DamageInfo info)? modifyDamageFn;

  @override
  String get label => name;
  @override
  bool cannotLeave(Game g, Fighter f) => cannotLeaveFn?.call(g, f) ?? false;
  @override
  Iterable<ValueOp> valueOps(Game g, Side s) => valueOpsFn?.call(g, s) ?? const [];
  @override
  int minHealth(Game g, Fighter f) => minHealthFn?.call(g, f) ?? 0;
  @override
  int modifyDamage(Game g, Fighter target, int amount, DamageInfo info) =>
      modifyDamageFn?.call(g, target, amount, info) ?? amount;
}

typedef Effect = Future<void> Function(Fx x);

class CardScript {
  const CardScript({
    this.effect,
    this.immediately,
    this.during,
    this.after,
    this.uncancelable = false,
    this.resolvesOnDefeat = false,
    this.boosted,
    this.ongoing,
    this.canPlay,
    this.alsoAttack,
    this.alsoDefense,
    this.onReveal,
    this.target,
    this.onlyTarget,
    this.noEffects = false,
  });

  /// Scheme effect.
  final Effect? effect;
  final Effect? immediately;
  final Effect? during;
  final Effect? after;

  /// "This card's effects cannot be canceled."
  final bool uncancelable;

  /// Resolves even if the fighter was defeated in this combat (Houdini: All Part of the Show).
  final bool resolvesOnDefeat;

  /// Houdini's "BOOSTED WITH" effect, when the card is discarded to boost.
  final Effect? boosted;

  /// ONGOING schemes: the mod that is active while the card stays face up.
  final OngoingMod Function(Game g, Card card, Fighter fighter)? ongoing;

  /// Extra condition to play this scheme (missions) or this combat card.
  final bool Function(Game g, Player p, Fighter f)? canPlay;

  /// May also be played as an attack / defense even though its type says otherwise.
  final bool Function(Game g, Fighter f)? alsoAttack;
  final bool Function(Game g, Fighter f)? alsoDefense;

  /// Happens when the card is played, before cards are revealed (play face up, predict a value).
  final Effect? onReveal;

  /// Widens who this attack may target (Foul Purpose played face up).
  final bool Function(Game g, Fighter attacker, Fighter target)? target;

  /// Narrows who this attack may target ("This attack can only target a fighter adjacent to...").
  final bool Function(Game g, Fighter attacker, Fighter target)? onlyTarget;

  /// The card has no effects at all, so it can't be "canceled" (Excalibur).
  final bool noEffects;

  bool get hasCombatEffects => immediately != null || during != null || after != null;
}

/// An ongoing scheme's effect. It stays active while [card] is in its owner's in-play row.
abstract class OngoingMod extends Mod {
  OngoingMod(this.card);
  final Card card;
  Player get owner => card.owner;

  @override
  String get label => card.title;

  /// Checked at the end of the owner's turn; true discards the card.
  bool discardAtEndOfTurn(Game g) => false;
}

/// An ongoing scheme described inline by the card script.
class Ongoing extends OngoingMod {
  Ongoing(
    super.card, {
    this.discardIf,
    this.onStartOfTurn,
    this.blocksActions = false,
    this.ignoreDiscards = false,
    this.onAfterCombat,
    this.moveValueFn,
    this.boostBonus = 0,
    this.modifyDamageFn,
    this.valueOpsFn,
  });

  /// Checked at the end of the owner's turn.
  final bool Function(Game g, Ongoing m)? discardIf;
  final Future<void> Function(Game g, Ongoing m)? onStartOfTurn;

  /// "Your opponent can't gain actions."
  final bool blocksActions;

  /// "If an effect would cause you to discard a card from your hand, you may ignore it."
  final bool ignoreDiscards;
  final Future<void> Function(Game g, Ongoing m, Combat c)? onAfterCombat;
  final int Function(Game g, Fighter f, int v)? moveValueFn;
  final int boostBonus;
  final int Function(Game g, Fighter target, int amount, DamageInfo info)? modifyDamageFn;
  final Iterable<ValueOp> Function(Game g, Side s)? valueOpsFn;

  @override
  bool discardAtEndOfTurn(Game g) => discardIf?.call(g, this) ?? false;
  @override
  Future<void> startOfTurn(Game g, Player active) async {
    if (active == owner && onStartOfTurn != null) await onStartOfTurn!(g, this);
  }

  @override
  bool canGainActions(Game g, Player p) => !blocksActions || p == owner;
  @override
  bool mayIgnoreDiscard(Game g, Player p) => ignoreDiscards && p == owner;
  @override
  Future<void> afterCombat(Game g, Combat c) async {
    if (onAfterCombat != null) await onAfterCombat!(g, this, c);
  }

  @override
  int moveValue(Game g, Fighter f, int v) => moveValueFn?.call(g, f, v) ?? v;
  @override
  int boostValue(Game g, Card c, int v) => c.owner == owner && boostBonus != 0 ? v + boostBonus : v;
  @override
  int modifyDamage(Game g, Fighter target, int amount, DamageInfo info) =>
      modifyDamageFn?.call(g, target, amount, info) ?? amount;
  @override
  Iterable<ValueOp> valueOps(Game g, Side s) => valueOpsFn?.call(g, s) ?? const [];
}

/// The effect context a card or ability resolves in.
class Fx {
  Fx(this.game, this.me, {this.card, this.side, Fighter? fighter, this.target}) : _sourceFighter = fighter;

  final Game game;
  final Player me;
  final Card? card;

  /// The side of combat this card was played on (null for schemes and abilities).
  final Side? side;
  final Fighter? _sourceFighter;

  /// The opponent a scheme was aimed at ("choose an opponent") in multi-opponent games.
  final Player? target;

  /// The fighter who played the card ("your fighter").
  Fighter get fighter => side?.fighter ?? _sourceFighter!;

  /// "Your opponent": in combat, the other player in the combat; otherwise the chosen opponent.
  Player get opp => side?.other.player ?? target ?? game.enemiesOf(me).first;

  /// Every opponent still in the game ("each opponent").
  Iterable<Player> get opponents => game.enemiesOf(me);
  bool isFoe(Fighter f) => f.isEnemyOf(me);
  bool isFriend(Fighter f) => f.isFriendOf(me);
  Combat get combat => side!.combat;
  bool get inCombat => side != null;
  Side get mySide => side!;
  Side get oppSide => side!.other;

  /// The opposing fighter in this combat.
  Fighter get oppFighter => side!.other.fighter;
  Card? get oppCard => side!.other.card;
  bool get attacking => side!.isAttacker;
  bool get defending => !side!.isAttacker;
  bool get won => combat.won(me);
  bool get lost => !combat.won(me);
  int get damageDealt => combat.combatDamage;
  Fighter get hero => me.heroFighter;
  Board get board => game.board;

  // -- shorthands -------------------------------------------------------------------------------
  Future<List<Card>> draw([int n = 1, Player? who]) => game.draw(who ?? me, n);
  Future<int> damage(Fighter f, int n) => game.damage(f, n, info: DamageInfo(source: _src, card: card, by: me));
  Future<int> heal(Fighter f, int n) => game.heal(f, n);
  Future<List<int>?> move(Fighter f, int upTo, {bool throughOpp = false, String? text}) =>
      game.moveFighter(f, upTo, chooser: me, throughOpp: throughOpp, text: text, source: card);
  Future<bool> place(Fighter f, Iterable<int> spaces, {String? text, bool optional = false}) =>
      game.placeFighter(f, spaces, chooser: me, text: text, optional: optional, source: card);
  void gainActions([int n = 1]) => game.gainActions(me, n);
  void cancelOpponent() => game.cancel(oppSide);
  void cancelOpponentAfter() => game.cancel(oppSide, afterOnly: true);
  void ignoreOpponentValue() => game.ignoreValue(oppSide);
  void setValue(int v, [String? label]) => game.addOp(mySide, ValueOp.set(v, label ?? card!.title));
  void addValue(int v, [String? label]) => game.addOp(mySide, ValueOp.add(v, label ?? card!.title));
  Future<bool> boostThis({bool blind = false, String? text}) => game.boostCard(mySide, blind: blind, text: text);

  Fighter? get _src => side?.fighter ?? _sourceFighter;

  Future<Fighter?> chooseFighter(Iterable<Fighter> options, String text,
          {Intent intent = Intent.none, bool optional = false, Player? who}) =>
      game.chooseFighter(who ?? me, options, text, intent: intent, optional: optional, source: card);
  Future<int?> chooseSpace(Iterable<int> options, String text,
          {Intent intent = Intent.none, bool optional = false, Object? subject, Player? who}) =>
      game.chooseSpace(who ?? me, options, text, intent: intent, optional: optional, subject: subject, source: card);
  Future<bool> yesNo(String text, {Intent intent = Intent.help, Player? who}) =>
      game.yesNo(who ?? me, text, intent: intent, source: card);
  Future<int> option(List<String> options, String text, {Player? who, Intent intent = Intent.help}) =>
      game.chooseOption(who ?? me, options, text, intent: intent, source: card);
  Future<List<Card>> discard(Player who, int n, {bool random = false, Player? chooser}) =>
      game.discardFromHand(who, n, random: random, chooser: chooser, by: me, source: card);

  // -- board queries ----------------------------------------------------------------------------
  Iterable<Fighter> get myFighters => me.onBoard;
  /// Every opposing fighter on the board.
  Iterable<Fighter> get enemies => game.enemyFighters(me);
  bool adjacent(Fighter a, Fighter b) => game.adjacent(a, b);
  Iterable<Fighter> adjacentTo(Fighter f) => game.adjacentFighters(f);
  Iterable<Fighter> enemiesAdjacentTo(Fighter f) => game.adjacentFighters(f).where((o) => o.isEnemyOf(f.owner));
  bool sameZone(Fighter a, Fighter b) => game.sameZone(a, b);
  Iterable<Fighter> inZoneOf(Fighter f) => game.fightersInZoneOf(f);
  Iterable<int> zoneSpaces(Fighter f) => game.zoneSpaces(f);
  Iterable<int> get allSpaces => game.board.spaceIds;
  Iterable<int> get emptySpaces => game.emptySpaces();

  Fighter? fighterNamed(String id) {
    for (final f in me.fighters) {
      if (f.id == id) return f;
    }
    return null;
  }
}

abstract class HeroScript extends Mod {
  late Game game;
  late Player me;

  /// The hero's current name (Jekyll & Hyde, Moon Knight's identities, Yennefer or Triss).
  String get heroName => me.hero.name;
  AttackType attackTypeOf(Fighter f) => f.def.attack;

  /// Card scripts by upper-cased title. Shared cards come from the common library.
  Map<String, CardScript> get cards;
  CardScript? scriptFor(Card c) => cards[c.def.upperTitle] ?? game.commonCards[c.def.upperTitle];

  int get startingHand => 5;

  /// Pre-game choices that change the deck (Geralt's gear).
  Future<void> beforeDeck() async {}

  /// Which cards make up the deck. Default: every card in its printed number of copies.
  Iterable<CardDef> deckCards() sync* {
    for (final c in me.hero.cards) {
      for (var i = 0; i < c.copies; i++) {
        yield c;
      }
    }
  }

  /// After the hero is placed in their start space (Alice's size, Invisible Man's fog).
  Future<void> afterHeroPlaced() async {}

  /// Fighters that start off the board (Sun Wukong's Clones).
  bool startsInReserve(Fighter f) => false;

  /// Large fighters (T. Rex) occupy their space and the one they last moved from.
  bool isLarge(Fighter f) => false;

  /// Small fighters (Squirrel Girl's squirrels): up to 4 share a space with one other fighter,
  /// opposing fighters move through them, and damage to one hits every one of its kind there.
  bool isSmall(Fighter f) => false;

  /// Places sidekicks (and any other heroes, like Dagger) at the start of the game: in the
  /// hero's zone, one by one.
  Future<void> placeSidekicks() async {
    final hero = me.heroFighter;
    for (final f in me.fighters.where((f) => f != hero && !f.reserve && f.space == null)) {
      final options = game.board.zoneOf(hero.space!).where(game.isEmpty).toList();
      final spaces = options.isNotEmpty ? options : game.emptySpaces().toList();
      final s = await game.chooseSpace(me, spaces, 'Place ${f.name} in ${hero.name}\'s zone',
          intent: Intent.moveOwn, subject: f);
      if (s != null) {
        f.space = s;
        await game.emit(FighterPlacedAtStart(f));
      }
    }
  }

  /// After the starting hand is drawn (Black Widow's Moscow Protocol is added before).
  Future<void> beforeStartingHand() async {}

  /// Whether [f] may play [c] (the "used by" restriction). Overridden by heroes with forms.
  bool fighterMayUse(Card c, Fighter f) => c.def.isAny || c.def.fighters.contains(f.id);

  /// Status chips for the HUD (Alice is BIG, 2 Rage, coils charged...).
  List<String> status() => const [];

  /// Cards this hero keeps on the table outside the hand (Pandora's MISERIES, Titania's
  /// GLAMOURS...), open information drawn on the player's plate and in its card tray.
  List<OpenZone> openZones() => const [];

  /// Rules a player needs beside the identity card (set rules, spells, the line so far), shown
  /// with the identity card during a match.
  List<String> reference() => const [];

  /// Draw step of a maneuver (Donatello may draw 2 and put one back).
  Future<void> maneuverDraw(int n) => game.draw(me, n);

  /// Movement step of a maneuver for one fighter (Houdini may place instead when boosted).
  Future<void> maneuverMove(Fighter f, int allowance, {required bool boosted}) async {
    await game.moveFighter(f, allowance, chooser: me);
  }

  /// Right after this hero's attack card is chosen, before the defender picks (King Arthur's
  /// face-down boost).
  Future<void> onAttackCardChosen(Combat c) async {}

  /// Who actually takes damage meant for [f] (Yennenga may shift it to her Archers).
  Future<Map<Fighter, int>> splitDamage(Fighter f, int n, DamageInfo info) async => {f: n};

  /// Krang's Die of Ultimate Destruction. ASSUMPTION: no public source lists its faces.
  static const dieFaces = [0, 1, 1, 2, 2, 3];

  /// Rolls the die for a '?' effect; Krang may reroll by deactivating machines.
  Future<int> rollDie(String why) async {
    final v = dieFaces[game.rng.nextInt(dieFaces.length)];
    await game.emit(StatusChanged(me, 'Die of Ultimate Destruction ($why): ${v == 0 ? 'blank' : v}'));
    return v;
  }

  /// Cards held outside the hand that may only be used to BOOST (Black Panther's Vibranium
  /// Suit; they can belong to other players).
  final List<Card> stored = [];

  /// After this player BOOSTs (Vibranium Suit: draw 1 card).
  Future<void> afterBoost() async {}

  /// Opponent cards this player has seen (looked at a hand, revealed), for the AI.
  final Set<Card> known = {};
  void seen(Iterable<Card> cards) => known.addAll(cards);

  /// The pile [c] goes to when it would be discarded (the Wayward Sisters' cauldron).
  List<Card> discardPileFor(Card c) => c.owner.discard;

  /// Cards set aside by a hero ability, outside hand, deck, discard pile and play (the
  /// Wayward Sisters' cauldron).
  final List<Card> aside = [];

  /// Where a played card goes when it leaves play. Return true if handled (Loki's tricks).
  Future<bool> disposePlayed(Card c) async => false;
}

/// Logged when a sidekick is placed during setup.
class FighterPlacedAtStart extends GameEvent {
  const FighterPlacedAtStart(this.fighter);
  final Fighter fighter;
  @override
  String get log => '';
}
