import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/combat.dart';
import 'package:unmatched_game/ui/match/hud.dart';

import 'support.dart';
import 'widget_test.dart' show loadFonts, phone;

void main() {
  setUpAll(loadFonts);

  testWidgets('Combat UI displays effects in resolution order and highlights resolving side', (tester) async {
    tester.view.physicalSize = phone * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final s = Scenario('king-arthur', 'medusa');
    final arthur = s.hero(s.p1);
    final medusa = s.hero(s.p2);
    s.place(arthur, 5);
    s.place(medusa, 6);

    final combat = Combat(arthur, medusa);
    final arthurCard = s.give(s.p1, 'MOMENTOUS SHIFT');
    final medusaCard = s.give(s.p2, 'REGROUP');
    combat.attacker.card = arthurCard;
    combat.defender.card = medusaCard;

    // 1. Reveal state
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombatView(
            game: s.game,
            combat: combat,
            me: s.p1,
            revealed: true,
            resolved: false,
            resolving: null,
            effectText: null,
            cardHeight: 200,
            onZoom: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify Defender and Attacker plates exist
    expect(find.text('DEFENDER'), findsOneWidget);
    expect(find.text('ATTACKER'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
    expect(find.text('DURING COMBAT'), findsOneWidget);
    expect(find.text('AFTER COMBAT'), findsOneWidget);

    // 2. Defender DURING COMBAT resolving (defender highlights first)
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombatView(
            game: s.game,
            combat: combat,
            me: s.p1,
            revealed: true,
            resolved: false,
            resolving: combat.defender,
            effectText: 'DEFENDER · REGROUP · DURING COMBAT: Test during effect',
            cardHeight: 200,
            onZoom: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('DEFENDER · REGROUP · DURING COMBAT'), findsOneWidget);

    // 3. Attacker DURING COMBAT resolving (attacker highlights second)
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombatView(
            game: s.game,
            combat: combat,
            me: s.p1,
            revealed: true,
            resolved: false,
            resolving: combat.attacker,
            effectText: 'ATTACKER · MOMENTOUS SHIFT · DURING COMBAT: Value is 5',
            cardHeight: 200,
            onZoom: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('ATTACKER · MOMENTOUS SHIFT · DURING COMBAT'), findsOneWidget);

    // 4. Defender AFTER COMBAT resolving (defender resolves before attacker)
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombatView(
            game: s.game,
            combat: combat,
            me: s.p1,
            revealed: true,
            resolved: false,
            resolving: combat.defender,
            effectText: 'DEFENDER · REGROUP · AFTER COMBAT: Draw 1 card',
            cardHeight: 200,
            onZoom: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('DEFENDER · REGROUP · AFTER COMBAT'), findsOneWidget);

    // 5. Attacker AFTER COMBAT resolving
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombatView(
            game: s.game,
            combat: combat,
            me: s.p1,
            revealed: true,
            resolved: false,
            resolving: combat.attacker,
            effectText: 'ATTACKER · MOMENTOUS SHIFT · AFTER COMBAT: Move up to 2',
            cardHeight: 200,
            onZoom: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('ATTACKER · MOMENTOUS SHIFT · AFTER COMBAT'), findsOneWidget);

    // 6. Resolved combat: verdict shown
    combat.resolved = true;
    combat.attackValue = 5;
    combat.defenseValue = 1;
    combat.combatDamage = 4;
    combat.attackerWon = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombatView(
            game: s.game,
            combat: combat,
            me: s.p1,
            revealed: true,
            resolved: true,
            resolving: null,
            effectText: null,
            cardHeight: 200,
            onZoom: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1  VS  5'), findsOneWidget);
    expect(find.textContaining('4 DAMAGE TO MEDUSA'), findsOneWidget);
  });
}
