/// Little Red Riding Hood vs. Beowulf.
library;

import '../combat.dart';
import '../events.dart';
import '../game.dart';
import '../hero_script.dart';
import '../prompt.dart';
import '../state.dart';
import 'common.dart';

// =============================================================================== Little Red

/// Symbols: W = wolf, R = rose, A = axes, * = basket (counts as any one symbol).
const _symbols = {
  'NEVER LEAVE THE PATH': 'W',
  'A GRIMM TALE': 'R',
  'ONCE UPON A TIME': 'R',
  'STONES IN THE BELLY': 'R',
  'WHAT BIG EYES YOU HAVE': 'W',
  'WHAT BIG EARS YOU HAVE': 'W',
  "THE WOLF'S SKIN": 'A',
  'LONG HAVE I SOUGHT YOU': 'A',
  'WHAT A TERRIBLE BIG MOUTH YOU HAVE': 'A',
  'WHAT LARGE HANDS YOU HAVE': 'W',
  "WHAT'S THAT IN MY BASKET?": '*',
};
const symbolNames = {'W': 'Wolf', 'R': 'Rose', 'A': 'Axes', '*': 'Basket (any)'};

/// Resolve an effect on a card you play only if its symbol matches the item in your basket: the
/// symbol of the top card of your discard pile. The basket itself sits at the bottom of the
/// discard pile and counts as any one symbol.
class LittleRed extends HeroScript {
  static String symbolOf(Card c) =>
      c.def.upperTitle == 'INTO THE WOODS' ? const ['W', 'R', 'A'][c.copy % 3] : _symbols[c.def.upperTitle] ?? '*';

  String get basket => me.discard.isEmpty ? '*' : symbolOf(me.discard.last);
  bool has(String s) => basket == '*' || basket == s;

  @override
  List<String> status() => ['Basket: ${symbolNames[basket]}'];

  @override
  Map<String, CardScript> get cards => {
        'NEVER LEAVE THE PATH': CardScript(effect: (x) async {
          if (has('W')) {
            await x.place(x.hero, x.allSpaces, text: 'Place Little Red in any space');
            x.gainActions(1);
          }
          if (has('A')) {
            for (final f in enemiesInZone(x, x.hero).toList()) {
              await x.damage(f, 2);
            }
          }
          if (has('R')) await x.draw(3);
        }),
        'A GRIMM TALE': CardScript(effect: (x) => x.heal(x.hero, has('W') ? 4 : 2)),
        'ONCE UPON A TIME': CardScript(after: (x) async {
          if (has('A')) await x.damage(x.oppFighter, 3);
        }),
        'STONES IN THE BELLY': CardScript(during: (x) async {
          if (has('A')) await ambush(x);
        }),
        'WHAT BIG EYES YOU HAVE': CardScript(immediately: (x) async {
          x.cancelOpponent();
          if (has('R')) x.ignoreOpponentValue();
        }),
        'WHAT BIG EARS YOU HAVE': CardScript(alsoDefense: (g, f) => has('A')),
        "THE WOLF'S SKIN": CardScript(after: (x) async {
          if (has('W')) await x.draw(2);
        }),
        'INTO THE WOODS': CardScript(effect: (x) async {
          await x.move(x.hero, 3);
          x.gainActions(1);
        }),
        'LONG HAVE I SOUGHT YOU': valueIf((x) => x.adjacent(x.fighter, x.oppFighter), 6),
        'WHAT A TERRIBLE BIG MOUTH YOU HAVE': CardScript(after: (x) async {
          final v = x.oppCard?.def.value ?? 0;
          if (has('W') && v > 0) await x.damage(x.oppFighter, v);
        }),
        'WHAT LARGE HANDS YOU HAVE': CardScript(after: (x) async {
          final top = x.me.discard.lastOrNull;
          final opts = ['Return this card to your hand', if (has('R') && top != null) 'Return ${top.title} (top of discard pile)', 'Neither'];
          final i = await x.option(opts, 'What Large Hands You Have');
          if (opts[i].startsWith('Return this')) {
            await x.game.returnPlayedToHand(x.card!);
          } else if (opts[i] != 'Neither' && top != null) {
            await x.game.toHand(top, reason: ' (What Large Hands You Have)');
          }
        }),
        "WHAT'S THAT IN MY BASKET?": vanilla,
      };
}

// ================================================================================== Beowulf

/// Starts with 1 Rage; gains 1 Rage whenever he is dealt damage; maximum 3.
class Beowulf extends HeroScript {
  int rage = 1;

  Future<void> gainRage(int n) async {
    final before = rage;
    rage = (rage + n).clamp(0, 3);
    if (rage != before) await game.emit(StatusChanged(me, 'Beowulf has $rage Rage.'));
  }

  Future<int> spendRage(String text, {int min = 0, int? max, Intent intent = Intent.help}) async {
    final top = max == null ? rage : (max < rage ? max : rage);
    if (top < min || top == 0) return 0;
    final n = await game.chooseNumber(me, min, top, '$text (you have $rage Rage)');
    if (n > 0) await gainRage(-n);
    return n;
  }

  @override
  Future<void> onDamaged(Game g, Fighter f, int amount, DamageInfo info) async {
    if (f == me.heroFighter && amount > 0) await gainRage(1);
  }

  @override
  List<String> status() => ['RAGE $rage'];

  @override
  Map<String, CardScript> get cards => {
        'REMNANT OF VALOR': CardScript(effect: (x) async {
          final w = x.fighter;
          var hitBeowulf = false;
          for (final f in x.adjacentTo(w).toList()) {
            final d = await x.damage(f, 1);
            if (f == x.hero && d > 0) hitBeowulf = true;
          }
          if (hitBeowulf) x.gainActions(1);
        }),
        'THE ANCIENT HEIRLOOM': CardScript(
          uncancelable: true,
          during: (x) async {
            if (rage >= 2 && await x.yesNo('Spend 2 Rage to make The Ancient Heirloom 5?')) {
              await gainRage(-2);
              x.setValue(5);
            }
            if (rage >= 1 && x.me.hand.any((c) => c.def.canBoost) && await x.yesNo('Spend 1 Rage to BOOST it?')) {
              await gainRage(-1);
              if (!await x.game.boostCard(x.mySide, optional: false)) await gainRage(1);
            }
          },
        ),
        'THE WAR-KING': CardScript(during: (x) async {
          final n = await spendRage('The War-King: spend Rage (+2 each)');
          if (n > 0) x.addValue(2 * n, 'Rage spent ($n)');
        }),
        'HOT FOR THE BATTLE': CardScript(after: (x) async {
          if (x.hero.onBoard && x.fighter.onBoard && await x.yesNo('Wiglaf swaps spaces with Beowulf?', intent: Intent.none)) {
            await x.game.swap(x.fighter, x.hero);
          }
        }),
        'FATAL STRUGGLE': CardScript(after: (x) async {
          if (x.won) {
            await x.draw(2);
          } else {
            await x.draw(2, x.opp);
          }
        }),
        'EPIC POEM': CardScript(
          immediately: (x) => gainRage(1),
          during: (x) async => x.addValue(rage, 'Rage ($rage)'),
        ),
        'GOLDEN DRINKING HORN': CardScript(effect: (x) async {
          final n = await spendRage('Golden Drinking Horn: spend Rage (one effect each)', max: 3);
          final picks = await chooseDifferent(
              x, ['Draw 2 cards', 'Move Beowulf up to 4 spaces', 'Beowulf recovers 2 health'], n, 'Golden Drinking Horn');
          for (final p in picks) {
            switch (p) {
              case 0:
                await x.draw(2);
              case 1:
                await x.move(x.hero, 4);
              case 2:
                await x.heal(x.hero, 2);
            }
          }
        }),
        'NO CONTEST EXPECTETH': CardScript(after: (x) async {
          final t = x.oppFighter;
          if (x.attacking && x.won && t.isSidekick && t.alive && rage >= 3 &&
              await x.yesNo('Spend 3 Rage to defeat ${t.name}?')) {
            await gainRage(-3);
            await x.game.defeat(t);
          }
        }),
        'THE EQUAL OF GRENDEL': CardScript(immediately: (x) async {
          final v = x.oppCard?.def.value ?? 0;
          if (rage >= 2 && v > 0 && await x.yesNo('Spend 2 Rage to deal $v damage to the opposing fighter?')) {
            await gainRage(-2);
            await x.damage(x.oppFighter, v);
          }
        }),
        'VIGOR AND COURAGE': CardScript(effect: (x) async {
          final d = await x.discard(x.opp, 1, random: true);
          if (d.isNotEmpty) await gainRage(d.first.def.boost ?? 0);
        }),
      };
}

/// Shorthand for the value of a side in tests and AI.
int sideValue(Game g, Side s) => g.valueOf(s).total;
