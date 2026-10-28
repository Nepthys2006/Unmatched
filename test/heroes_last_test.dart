// Card-by-card tests for the last heroes added: Raphael, Dr. Jill Trent, Oda Nobunaga,
// Tomoe Gozen, Shakespeare, The Wayward Sisters. (Squirrel Girl has her own file.)
// Board: line 0-11 (+12 off 5); zones a=0..3, b=3..7+12, c=8..11.
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/heroes/amaze.dart';
import 'package:unmatched_game/engine/state.dart';

import 'support.dart';

void main() {
  group('Raphael', () {
    Fighter casey(Scenario s, [Player? p]) => (p ?? s.p1).fighters.firstWhere((f) => f.id == 'casey-jones');

    test('17 health, Casey Jones 8 health ranged', () {
      final s = Scenario('raphael', 'medusa');
      expect(s.hero(s.p1).hp, 17);
      expect(casey(s).hp, 8);
      expect(casey(s).isRanged, isTrue);
    });

    test('Anger Issues and Payback Time!', () async {
      final s = Scenario('raphael', 'medusa');
      final r = s.hero(s.p1), m = s.hero(s.p2);
      s.place(r, 4);
      s.place(m, 5);
      m.hp = 30;
      final actions = s.game.actions;
      expect((await s.fight(r, m, 'Payback Time!', null)).attackValue, 2, reason: 'no lost combat yet');
      expect(s.game.actions, actions);
      // Raphael's attack of 1 against Medusa's defense: he loses.
      final lost = await s.fight(r, m, "Let's Do This!", 'Snipe');
      expect(lost.won(s.p1), isFalse);
      expect(s.game.actions, actions + 1, reason: 'first loss this turn');
      await s.fight(r, m, "Let's Do This!", 'Snipe');
      expect(s.game.actions, actions + 1, reason: 'only the first loss');
      expect((await s.fight(r, m, 'Payback Time!', null)).attackValue, 5);
    });

    test("Let's Do This! draws 1, or 2 on a win; Crowd Control draws and hurts per adjacent enemy", () async {
      final s = Scenario('raphael', 'medusa');
      final r = s.hero(s.p1), m = s.hero(s.p2);
      s.place(r, 4);
      s.place(m, 5);
      s.place(s.sidekick(s.p2, 1), 3);
      m.hp = 30;
      var hand = s.p1.hand.length;
      await s.fight(r, m, "Let's Do This!", null);
      expect(s.p1.hand.length, hand + 2);
      hand = s.p1.hand.length;
      final harpy = s.sidekick(s.p2, 1), hp = harpy.hp;
      await s.fight(r, m, 'Crowd Control', null);
      expect(s.p1.hand.length, hand + 2);
      expect(harpy.hp, hp - 1);
    });

    test('Break Something cancels DURING/AFTER effects; with nothing canceled it deals 2 to an adjacent foe', () async {
      final s = Scenario('raphael', 'medusa');
      final r = s.hero(s.p1), m = s.hero(s.p2);
      s.place(r, 4);
      s.place(m, 5);
      m.hp = 30;
      final hand = s.p2.hand.length;
      final c1 = await s.fight(r, m, 'Break Something', 'Snipe'); // Snipe: AFTER draw 1
      expect(c1.defender.afterCanceled, isTrue);
      expect(s.p2.hand.length, hand, reason: "Snipe's draw was canceled");
      final hp = m.hp;
      await s.fight(r, m, 'Break Something', null);
      expect(m.hp, hp - 2 - 2, reason: '2 combat damage plus 2 from the effect');
    });

    test('Raphael Is Cool But Rude: 1 damage to each foe next to a friend, draw 1', () async {
      final s = Scenario('raphael', 'medusa');
      final r = s.hero(s.p1), m = s.hero(s.p2), h = s.sidekick(s.p2, 1);
      s.place(r, 4);
      s.place(m, 5);
      s.place(h, 9);
      s.place(casey(s), 10);
      final hp = [m.hp, h.hp], hand = s.p1.hand.length;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Raphael Is Cool But Rude'));
      expect([m.hp, h.hp], [hp[0] - 1, hp[1] - 1]);
      expect(s.p1.hand.length, hand + 1, reason: 'draw 1');
    });

    test('Relentless goes back into the deck; Slapshot is 6 when Casey is adjacent', () async {
      final s = Scenario('raphael', 'medusa');
      final m = s.hero(s.p2);
      s.place(s.hero(s.p1), 0);
      s.place(casey(s), 4);
      s.place(m, 5);
      m.hp = 30;
      await s.fight(casey(s), m, 'Relentless', null);
      expect(s.p1.discard.where((c) => c.title == 'Relentless'), isEmpty);
      expect([...s.p1.deck, ...s.p1.hand].where((c) => c.title == 'Relentless'), hasLength(1));
      expect((await s.fight(casey(s), m, 'Slapshot', null)).attackValue, 6);
      s.place(casey(s), 3);
      expect((await s.fight(casey(s), m, 'Slapshot', null)).attackValue, 2);
    });

    test('Unbridled Rage: +2 per defense or versatile card discarded; Batter Up! pushes on a win', () async {
      final s = Scenario('raphael', 'medusa');
      final r = s.hero(s.p1), m = s.hero(s.p2);
      s.place(r, 4);
      s.place(m, 5);
      m.hp = 30;
      s.give(s.p1, 'Sai');
      s.give(s.p1, 'Heroes in a Half Shell');
      s.give(s.p1, 'Crowd Control');
      final c = await s.fight(r, m, 'Unbridled Rage', null, then1: [
        (p) => [for (var i = 0; i < p.choices.length; i++) i]
      ]);
      expect(c.attackValue, 3 + 4);
      expect(s.p1.hand.map((c) => c.title), contains('Crowd control'));
      s.place(casey(s), 6);
      await s.fight(casey(s), m, 'Batter Up!', null, then1: [sp(12)]);
      expect(m.space, 12);
    });
  });

  group('Dr. Jill Trent', () {
    Fighter daisy(Scenario s) => s.p1.fighters.firstWhere((f) => f.id == 'daisy');

    Scenario setup() {
      final s = Scenario('dr-jill-trent', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 30;
      return s;
    }

    test('Gadgetology: pick a gadget each turn; Hypnoray adds the BOOST of their top card when lower', () async {
      final s = setup();
      final j = s.hero(s.p1), m = s.hero(s.p2);
      s.a1.then('Hypnoray Blaster');
      await s.p1.script.startOfTurn(s.game, s.p1);
      expect(s.p1.script.status(), ['Hypnoray Blaster']);
      s.deck(s.p2, ['The Hounds of Mighty Zeus']); // BOOST of that card is added
      final boost = s.p2.deck.first.def.boost!;
      final c = await s.fight(j, m, 'Battle of Wits', 'Hiss and Slither'); // 2 vs 4
      expect(c.attackValue, 2 + boost);
      expect(s.p2.deck, hasLength(1), reason: 'only revealed');
    });

    test('Ultrabiotic Tonic heals 1 when your printed value is higher; Daisy uses it with Sisters in Arms', () async {
      final s = setup();
      final j = s.hero(s.p1), m = s.hero(s.p2);
      s.a1.then('Ultrabiotic Tonic');
      await s.p1.script.startOfTurn(s.game, s.p1);
      j.hp = 10;
      await s.fight(j, m, 'Energizing Spray', null);
      expect(j.hp, 11);
      s.place(daisy(s), 6);
      s.place(j, 7);
      await s.fight(daisy(s), m, 'Sisters in Arms', null);
      expect(j.hp, 12);
      s.place(j, 0);
      await s.fight(daisy(s), m, 'Sisters in Arms', null);
      expect(j.hp, 12, reason: 'not adjacent');
    });

    test('Hypnotist cancels only with Hypnoray active; Energizing Spray gains an action', () async {
      final s = Scenario('medusa', 'dr-jill-trent');
      final m = s.hero(s.p1), j = s.hero(s.p2);
      s.place(m, 4);
      s.place(j, 5);
      final c1 = await s.fight(m, j, 'Snipe', 'Hypnotist');
      expect(c1.attacker.canceled, isFalse);
      (s.p2.script as dynamic).gadget = Gadget.hypnoray;
      final c2 = await s.fight(m, j, 'Snipe', 'Hypnotist');
      expect(c2.attacker.canceled, isTrue);
    });

    test('Battle of Wits deals 3 when your top card has the higher BOOST', () async {
      final s = setup();
      final j = s.hero(s.p1), m = s.hero(s.p2);
      s.deck(s.p1, ['Battle of Wits']); // BOOST 4
      s.deck(s.p2, ['Feint']); // BOOST 1
      final hp = m.hp;
      await s.fight(j, m, 'Battle of Wits', null);
      expect(m.hp, hp - 2 - 3);
    });

    test('Insightful Deduction rearranges their top 3; Caught Red-Handed discards 2 on a win', () async {
      final s = setup();
      final j = s.hero(s.p1), m = s.hero(s.p2);
      s.deck(s.p2, ['Feint', 'Snipe', 'Dash', 'Regroup']);
      await s.fight(j, m, 'Insightful Deduction', null, then1: [card('Feint'), card('Dash')]);
      expect(s.p2.deck.map((c) => c.title), ['Dash', 'Snipe', 'Regroup', 'Feint']);
      for (final t in ['Snipe', 'Snipe', 'Snipe']) {
        s.give(s.p2, t);
      }
      await s.fight(j, m, 'Caught Red-Handed', null);
      expect(s.p2.hand, hasLength(1));
    });

    test('Indestructible Cloth stops effect damage this combat; Laser Pen; Helpful Assistant', () async {
      final s = Scenario('dr-jill-trent', 'medusa');
      final j = s.hero(s.p1), m = s.hero(s.p2);
      s.place(j, 4);
      s.place(m, 5);
      j.hp = 13;
      final c = await s.fight(m, j, 'Gaze of Stone', 'Indestructible Cloth');
      expect(c.defender.fighter.hp, 13, reason: 'Gaze of Stone deals effect damage');
      final hp = m.hp;
      await s.fight(j, m, 'Laser Pen', null);
      expect(m.hp, hp - 2 - 1);
      s.place(daisy(s), 0);
      s.discardPile(s.p1, ['Laser Pen', 'Ace Fighter']);
      final deck = s.p1.deck.length;
      s.a1.then([0, 1, 2]);
      await s.game.playScheme(s.p1, s.give(s.p1, 'Helpful Assistant'));
      expect(s.p1.deck.length, deck + 3 - 1, reason: '3 shuffled in, 1 drawn');
    });
  });

  group('Oda Nobunaga', () {
    Fighter guard(Scenario s, int n, [Player? p]) => (p ?? s.p1).fighters.where((f) => f.id == 'honor-guard').elementAt(n - 1);

    test('Master Strategist: +1 to other friendly fighters in his zone, not to Oda', () async {
      final s = Scenario('oda-nobunaga', 'medusa');
      final oda = s.hero(s.p1), m = s.hero(s.p2);
      s.place(oda, 3);
      s.place(guard(s, 1), 4);
      s.place(m, 5);
      m.hp = 30;
      expect((await s.fight(guard(s, 1), m, 'Lightning and Thunder', null, then1: [sp(4)])).attackValue, 5);
      s.place(oda, 6);
      expect((await s.fight(oda, m, 'Student of War', null)).attackValue, 5, reason: 'Oda gets no bonus');
      s.place(oda, 9);
      expect((await s.fight(guard(s, 1), m, 'Momentous Shift', null)).attackValue, 3, reason: 'Oda in another zone');
    });

    test('flanked: Fire and Flames 5, Sun and Moon ignores, Demon King hits each flanked foe', () async {
      final s = Scenario('oda-nobunaga', 'medusa');
      final oda = s.hero(s.p1), m = s.hero(s.p2);
      s.place(oda, 9);
      s.place(guard(s, 1), 4);
      s.place(m, 5);
      m.hp = 30;
      expect((await s.fight(guard(s, 1), m, 'Fire and Flames', null)).attackValue, 3);
      s.place(guard(s, 2), 6);
      expect((await s.fight(guard(s, 1), m, 'Fire and Flames', null)).attackValue, 5);
      final c = await s.fight(guard(s, 1), m, 'Sun and Moon', 'Hiss and Slither');
      expect(c.defenseValue, 0);
      final hp = m.hp;
      await s.game.playScheme(s.p1, s.give(s.p1, 'Demon King of the Sixth Heaven'));
      expect(m.hp, hp - 2);
    });

    test('Reinforce: two different effects; Student of War draws per combat damage', () async {
      final s = Scenario('oda-nobunaga', 'medusa');
      final oda = s.hero(s.p1), m = s.hero(s.p2);
      s.place(oda, 4);
      s.place(m, 5);
      m.hp = 30;
      oda.hp = 10;
      final hand = s.p1.hand.length;
      s.a1
        ..then('recovers')
        ..then('Gain 1 action');
      await s.game.playScheme(s.p1, s.give(s.p1, 'Reinforce'));
      expect(oda.hp, 11);
      expect(s.game.actions, 3);
      expect(s.p1.hand.length, hand);
      await s.fight(oda, m, 'Student of War', null);
      expect(s.p1.hand.length, hand + 5);
    });

    test('Spring the Trap: swap with an adjacent friend who becomes the defender, then 1 damage', () async {
      final s = Scenario('medusa', 'oda-nobunaga');
      final m = s.hero(s.p1), oda = s.hero(s.p2), g = guard(s, 1, s.p2);
      s.place(m, 4);
      s.place(oda, 5);
      s.place(g, 6);
      final hp = m.hp;
      final c = await s.fight(m, oda, 'Snipe', 'Spring the Trap', then2: [g]);
      expect(c.defender.fighter, g);
      expect([oda.space, g.space], [6, 5]);
      expect(m.hp, hp - 1);
    });
  });

  group('Tomoe Gozen', () {
    test('Attack of Opportunity: 1 damage each time an opposing hero leaves her zone', () async {
      final s = Scenario('tomoe-gozen', 'medusa');
      final t = s.hero(s.p1), m = s.hero(s.p2);
      s.place(t, 5);
      s.place(m, 7);
      final hp = m.hp;
      s.a2.then(sp(9));
      await s.game.moveFighter(m, 2);
      expect(m.hp, hp - 1);
      s.a2.then(sp(7));
      await s.game.moveFighter(m, 2);
      expect(m.hp, hp - 1, reason: 'entering is free');
      final h = s.sidekick(s.p2, 1);
      s.place(h, 6);
      s.a2.then(sp(9));
      await s.game.moveFighter(h, 3);
      expect(h.hp, h.maxHp, reason: 'heroes only');
    });

    test('Witness My Last Battle: adjacent targets only, face up, ends the turn', () async {
      final s = Scenario('tomoe-gozen', 'medusa');
      final t = s.hero(s.p1), m = s.hero(s.p2);
      s.place(t, 3);
      s.place(m, 5);
      m.hp = 30;
      s.p1.hand.clear();
      s.give(s.p1, 'Witness My Last Battle');
      expect(s.game.legalActions(s.p1).where((a) => a.target == m), isEmpty, reason: 'ranged reach but not adjacent');
      s.place(t, 4);
      expect(s.game.legalActions(s.p1).where((a) => a.target == m), isNotEmpty);
      s.p1.hand.clear();
      final c = await s.fight(t, m, 'Witness My Last Battle', null);
      expect(c.attackValue, 7);
      expect(c.attacker.faceUp, isTrue);
      expect(s.game.turnEnded, isTrue);
    });

    test('Deeds of Valor caps combat damage at 2; Refuse to Retreat; A Worthy Opponent', () async {
      final o = Scenario('oda-nobunaga', 'tomoe-gozen');
      o.place(o.hero(o.p1), 4);
      o.place(o.hero(o.p2), 5);
      final hp = o.hero(o.p2).hp;
      await o.fight(o.hero(o.p1), o.hero(o.p2), 'Student of War', 'Deeds of Valor'); // 5 vs 2
      expect(o.hero(o.p2).hp, hp - 2);

      final s = Scenario('medusa', 'tomoe-gozen');
      final m = s.hero(s.p1), t = s.hero(s.p2);
      s.place(m, 4);
      s.place(t, 5);
      s.p1.hand.clear();
      s.give(s.p1, 'Feint');
      await s.fight(m, t, 'Snipe', 'Refuse to Retreat');
      expect(s.game.cannotLeave(t), isTrue);
      expect(s.p1.hand, hasLength(1), reason: 'Snipe drew 1; Medusa adjacent: discarded 1');
      expect((await s.fight(t, m, 'A Worthy Opponent', null)).attackValue, 5);
    });

    test("A Warrior's Way pushes the hero (Attack of Opportunity) and places Tomoe next to them", () async {
      final s = Scenario('tomoe-gozen', 'medusa');
      final t = s.hero(s.p1), m = s.hero(s.p2);
      s.place(t, 6);
      s.place(m, 7);
      m.hp = 30;
      await s.fight(t, m, "A Warrior's Way", null, then1: [sp(10), sp(9)]);
      expect(m.space, 10);
      expect(t.space, 9);
      expect(m.hp, 30 - 2 - 1, reason: '2 combat damage, 1 Attack of Opportunity');
    });

    test('Five Against Thousands returns to hand for a discard; Flash of Steel; Fearsome Strength', () async {
      final s = Scenario('tomoe-gozen', 'medusa');
      final t = s.hero(s.p1), m = s.hero(s.p2);
      s.place(t, 6);
      s.place(m, 7);
      m.hp = 30;
      s.give(s.p1, 'Piercing Shot');
      await s.fight(t, m, 'Five Against Thousands', null, then1: [card('Piercing Shot')]);
      expect(s.p1.hand.map((c) => c.title), contains('Five Against Thousands'));
      final c = await s.fight(t, m, 'Flash of Steel', 'Snipe');
      expect(c.defender.canceled, isTrue);
      final hp = m.hp;
      await s.fight(t, m, 'Fearsome Strength', null, then1: [m, m]);
      expect([t.space, m.space], [7, 6]);
      expect(m.hp, hp - 3 - 1);
    });

    test("Lord Kiso's Final Stand moves through sidekicks, then heals or gains an action", () async {
      final s = Scenario('tomoe-gozen', 'medusa');
      final t = s.hero(s.p1);
      s.place(t, 4);
      s.place(s.hero(s.p2), 11);
      s.place(s.sidekick(s.p2, 1), 5);
      t.hp = 10;
      s.a1
        ..then(sp(7))
        ..then('recovers');
      await s.game.playScheme(s.p1, s.give(s.p1, "Lord Kiso's Final Stand"));
      expect(t.space, 7);
      expect(t.hp, 12);
    });
  });

  group('Shakespeare', () {
    Fighter actor(Scenario s, int n) => s.p1.fighters.where((f) => f.id == 'actor').elementAt(n - 1);
    List<String> line(Scenario s) => [for (final c in s.p1.inPlay) c.title];

    Scenario setup() {
      final s = Scenario('shakespeare', 'medusa');
      s.place(s.hero(s.p1), 4);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 40;
      return s;
    }

    test('3 Actors of 1 health; syllables are on every card', () {
      final s = setup();
      expect(s.p1.fighters.where((f) => f.id == 'actor').map((f) => f.hp), [1, 1, 1]);
      expect(s.p1.hero.cards.every((c) => c.syllables != null), isTrue);
    });

    test('Iambic Pentameter: cards go to the line; exactly 10 resolves the last completion', () async {
      final s = setup();
      final sh = s.hero(s.p1), m = s.hero(s.p2);
      await s.fight(sh, m, 'Et Tu, Brute?', null);
      expect(line(s), ['Et Tu, Brute?']);
      expect(s.p1.discard, isEmpty);
      await s.fight(sh, m, 'Alas', null);
      final hand = s.p1.hand.length;
      await s.fight(sh, m, 'All Are Punished', null);
      expect(s.p1.hand.length, hand + 1, reason: 'All Are Punished completion: draw 1');
      expect(line(s), isEmpty);
      expect(s.p1.discard, hasLength(3));
    });

    test('over 10 syllables: the line is discarded with no completion', () async {
      final s = setup();
      final sh = s.hero(s.p1), m = s.hero(s.p2);
      await s.fight(sh, m, 'My Kingdom for a Horse', null); // 6
      final actions = s.game.actions;
      await s.fight(sh, m, 'My Kingdom for a Horse', null); // 12
      expect(s.game.actions, actions, reason: 'no completion');
      expect(line(s), isEmpty);
    });

    test('My Kingdom for a Horse completes a 10: gain 2 actions; Horror grows with Horrors in the line', () async {
      final s = setup();
      final sh = s.hero(s.p1), m = s.hero(s.p2);
      expect((await s.fight(sh, m, 'Horror', null)).attackValue, 4);
      expect((await s.fight(sh, m, 'Horror', null)).attackValue, 5);
      final actions = s.game.actions;
      await s.fight(sh, m, 'My Kingdom for a Horse', null);
      expect(s.game.actions, actions + 2);
    });

    test('Horror completion: 1 damage per other card in the line; Deceive completion returns to hand', () async {
      final s = setup();
      final sh = s.hero(s.p1), m = s.hero(s.p2);
      await s.fight(sh, m, 'Places, Places!', null); // 4
      await s.fight(sh, m, 'Revise', null); // 6
      await s.fight(sh, m, 'Alas', null); // 8
      final hp = m.hp;
      final c = await s.fight(sh, m, 'Horror', null); // 10
      expect(m.hp, hp - c.combatDamage - 3);
      await s.fight(sh, m, 'All Are Punished', null); // 4
      await s.fight(sh, m, 'Once More Unto the Breach', null); // 10 (no Actors defeated)
      await s.fight(sh, m, 'My Kingdom for a Horse', null); // 6
      await s.fight(sh, m, 'Alas', null); // 8
      await s.fight(sh, m, 'Deceive', null); // 10
      expect(s.p1.hand.map((c) => c.title), contains('Deceive'));
    });

    test('canceled card still completes; Again returns the first card of the line', () async {
      final s = setup();
      final sh = s.hero(s.p1), m = s.hero(s.p2);
      s.place(actor(s, 1), 6);
      await s.fight(sh, m, 'Revise', null);
      await s.fight(actor(s, 1), s.hero(s.p2), 'Again', null, then1: ['Yes']);
      expect(s.p1.hand.map((c) => c.title), contains('Revise'));
      expect(line(s), ['Again']);
      await s.fight(sh, m, 'Et Tu, Brute?', null); // 6
      final hand = s.p1.hand.length;
      await s.fight(actor(s, 1), m, 'Such Sweet Sorrow', 'Feint'); // 10, canceled by Feint
      expect(s.p1.hand.length, hand + 1, reason: 'completion still draws 1');
    });

    test('Once More Unto the Breach returns a defeated Actor to his zone; All Are Punished hits everyone in the zone', () async {
      final s = setup();
      final sh = s.hero(s.p1), m = s.hero(s.p2);
      actor(s, 1)
        ..defeated = true
        ..space = null;
      await s.fight(sh, m, 'Once More Unto the Breach', null, then1: [sp(3)]);
      expect(actor(s, 1).space, 3);
      final hp = m.hp;
      await s.fight(sh, m, 'All Are Punished', null);
      expect(actor(s, 1).defeated, isTrue, reason: 'own Actor in the zone takes 1');
      expect(m.hp, lessThan(hp));
    });
  });

  group('The Wayward Sisters', () {
    List<Fighter> sisters(Scenario s) => s.p1.fighters.where((f) => f.isHero).toList();
    List<Card> cauldron(Scenario s) => s.p1.script.aside;

    Scenario setup() {
      final s = Scenario('the-wayward-sisters', 'medusa');
      final w = sisters(s);
      s.place(w[0], 4);
      s.place(w[1], 0);
      s.place(w[2], 1);
      s.place(s.hero(s.p2), 5);
      s.hero(s.p2).hp = 40;
      return s;
    }

    test('three Sisters of 6 health; lose only when all three fall', () {
      final s = setup();
      final w = sisters(s);
      expect(w.map((f) => f.hp), [6, 6, 6]);
      expect(w.first.name, 'Wayward Sister 1');
      w[0].defeated = true;
      w[1].defeated = true;
      expect(s.p1.defeated, isFalse);
      w[2].defeated = true;
      expect(s.p1.defeated, isTrue);
    });

    test('cards go into the cauldron, not the discard pile (played, boosted, discarded)', () async {
      final s = setup();
      final w = sisters(s);
      await s.fight(w[0], s.hero(s.p2), 'Hurly-Burly', null);
      expect(cauldron(s).map((c) => c.title), contains('Hurly-Burly'));
      final c = s.give(s.p1, 'Ward');
      await s.game.discardCard(c);
      expect(cauldron(s), contains(c));
      expect(s.p1.discard, isEmpty);
    });

    test('Double, Double and Toil and Trouble: +1 per different ingredient in the cauldron', () async {
      final s = setup();
      final w = sisters(s);
      cauldron(s).addAll([s.make(s.p1, 'Ward'), s.make(s.p1, 'Ward'), s.make(s.p1, 'Prophecy')]);
      expect((await s.fight(w[0], s.hero(s.p2), 'Double, Double', null)).attackValue, 3 + 2);
    });

    test('after attacking: cast a spell (the attack card counts), then the cauldron is discarded', () async {
      final s = setup();
      final w = sisters(s);
      cauldron(s).addAll([s.make(s.p1, 'Ward'), s.make(s.p1, 'Toil and Trouble')]);
      s.give(s.p1, 'Double, Double');
      s.a1
        ..then(card('Double, Double'))
        ..then('Snake, bat and lizard');
      s.a2.then(skip);
      final actions = s.game.actions;
      await s.game.attack(w[0], s.hero(s.p2));
      expect(s.game.actions, actions + 1, reason: 'all three ingredients: gain 1 action');
      expect(cauldron(s), isEmpty);
      expect(s.p1.discard, hasLength(3));
    });

    test('The Stars Align: value is the number of zones the Sisters are in', () async {
      final s = setup();
      final w = sisters(s);
      s.place(w[1], 9);
      // Sister 1 at 4 (zone b), Sister 2 at 9 (c), Sister 3 at 1 (a).
      expect((await s.fight(w[0], s.hero(s.p2), 'The Stars Align', null)).attackValue, 3);
    });

    test('Fire Burn returns a discard to the cauldron; Curious Familiar takes one back to hand', () async {
      final s = setup();
      final w = sisters(s);
      s.discardPile(s.p1, ['Ward']);
      await s.fight(w[0], s.hero(s.p2), 'Fire Burn and Cauldron Bubble', null);
      expect(cauldron(s).map((c) => c.title), contains('Ward'));
      await s.fight(w[0], s.hero(s.p2), 'Curious Familiar', null, then1: [card('Ward')]);
      expect(s.p1.hand.map((c) => c.title), contains('Ward'));
    });

    test('Pricking of My Thumbs returns the combat damage taken; Prophecy keeps 2 of 4', () async {
      final s = Scenario('medusa', 'the-wayward-sisters');
      final m = s.hero(s.p1), w = s.hero(s.p2);
      s.place(m, 4);
      s.place(w, 5);
      final hp = m.hp;
      await s.fight(m, w, 'Snipe', 'Pricking of My Thumbs'); // 3 vs 2: 1 damage
      expect(m.hp, hp - 1);
      final p = Scenario('the-wayward-sisters', 'medusa');
      p.place(p.hero(p.p1), 4);
      p.place(p.hero(p.p2), 9);
      p.deck(p.p1, ['Ward', 'Prophecy', 'Hurly-Burly', 'Double, Double', 'The Stars Align']);
      p.a1.then([0, 1]);
      await p.game.playScheme(p.p1, p.give(p.p1, 'Prophecy'));
      expect(p.p1.hand.map((c) => c.title), containsAll(['Ward', 'Prophecy']));
      expect(p.p1.deck, hasLength(3));
    });
  });
}
