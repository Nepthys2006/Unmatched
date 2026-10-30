// The main-screen Active Players list, profile cards and invite dialog, at phone and desktop
// sizes. Any exception or layout overflow fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/net/online_presence.dart';
import 'package:unmatched_game/net/profile_stats.dart';
import 'package:unmatched_game/ui/dialogs/active_players_drawer.dart';
import 'package:unmatched_game/ui/dialogs/invite_banner_dialog.dart';
import 'package:unmatched_game/ui/dialogs/player_profile_modal.dart';
import 'package:unmatched_game/ui/screens/menu_screen.dart';
import 'package:unmatched_game/ui/widgets.dart' show PlateButton;

import 'widget_test.dart' show boot, loadFonts, phone, smallPhone, desktop, sizeName;

Map<String, Object?> stats({int mmr = 1180, String hero = 'medusa'}) => {
  'totalMatches': 30,
  'wins': 19,
  'losses': 11,
  'overallWinRate': 63.3,
  'pvp': {'matches': 10, 'wins': 7, 'losses': 3, 'winRate': 70.0},
  'pve': {'matches': 20, 'wins': 12, 'losses': 8, 'winRate': 60.0},
  'mmr': mmr,
  'mainHero': hero,
  'top5': [
    {'heroId': hero, 'matches': 14, 'wins': 10, 'losses': 4},
    {'heroId': 'alice', 'matches': 9, 'wins': 5, 'losses': 4},
  ],
  'recent': [
    {'victory': true, 'heroId': hero, 'opponentName': 'Bravo', 'opponentHeroId': 'alice', 'mapId': 'blossom', 'mode': 'online', 'pvp': true, 'mmrChange': 14, 'timestamp': DateTime.now().toIso8601String()},
    {'victory': false, 'heroId': hero, 'opponentName': 'AI Hard', 'opponentHeroId': 'alice', 'mapId': 'blossom', 'mode': 'local', 'timestamp': DateTime.now().toIso8601String()},
  ],
};

OnlineUser user(String id, String name, String status, {Map<String, Object?>? stats}) => OnlineUser(id: id, name: name, status: status, stats: stats);

void main() {
  setUpAll(loadFonts);

  for (final size in [smallPhone, phone, desktop]) {
    group(sizeName(size), () {
      testWidgets('opening Active Players lists everyone and does not crash', (t) async {
        await boot(t, size, home: const MenuScreen());
        await t.pump(const Duration(seconds: 1));
        OnlinePresenceService.instance.debugSetUsers([
          user('a', 'Alpha', 'idle'),
          user('b', 'Bravo', 'matching', stats: stats()),
          user('c', 'Charlie', 'inGame', stats: stats(mmr: 1750, hero: 'alice')),
        ]);
        await t.tap(find.byTooltip('Active Players'));
        await t.pump(const Duration(seconds: 1));
        expect(find.text('ACTIVE PLAYERS'), findsOneWidget);
        expect(find.text('BRAVO'), findsOneWidget);
        // A player in a match can't be invited.
        expect(find.text('IN A MATCH'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('a long list scrolls without overflow', (t) async {
        await boot(t, size, home: const MenuScreen());
        await t.pump(const Duration(seconds: 1));
        OnlinePresenceService.instance.debugSetUsers([
          for (var i = 0; i < 25; i++) user('x$i', 'Player number $i with a very long name indeed', i % 3 == 0 ? 'matching' : 'idle', stats: stats(mmr: 900 + i * 40)),
        ]);
        await t.tap(find.byTooltip('Active Players'));
        await t.pump(const Duration(seconds: 1));
        await t.drag(find.byType(ListView).last, const Offset(0, -400));
        await t.pump(const Duration(milliseconds: 500));
        expect(t.takeException(), isNull);
      });

      testWidgets('inviting from the main screen tells the player and leaves the menu on screen', (t) async {
        await boot(t, size, home: const MenuScreen());
        await t.pump(const Duration(seconds: 1));
        OnlinePresenceService.instance.debugSetUsers([user('a', 'Alpha', 'idle', stats: stats())]);
        await t.tap(find.byTooltip('Active Players'));
        await t.pump(const Duration(seconds: 1));
        await t.tap(find.text('INVITE'));
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
        // Online play isn't configured in tests: the player is told, the menu survives.
        expect(find.byType(MenuScreen), findsOneWidget);
        expect(find.textContaining('Online play isn'), findsOneWidget);
        await t.pump(const Duration(seconds: 5));
        expect(t.takeException(), isNull);
      });

      testWidgets('a profile shows the main hero, MMR and separate PvP and AI win rates', (t) async {
        await boot(t, size, home: const MenuScreen());
        await t.pump(const Duration(seconds: 1));
        OnlinePresenceService.instance.debugSetUsers([user('b', 'Bravo', 'matching', stats: stats())]);
        await t.tap(find.byTooltip('Active Players'));
        await t.pump(const Duration(seconds: 1));
        await t.tap(find.text('BRAVO'));
        await t.pump(const Duration(seconds: 1));
        expect(find.byType(PlayerProfileModal), findsOneWidget);
        expect(find.text('VS PLAYERS'), findsOneWidget);
        expect(find.text('VS AI'), findsOneWidget);
        expect(find.text('70%'), findsOneWidget);
        expect(find.text('60%'), findsOneWidget);
        expect(find.text('1180'), findsWidgets);
        expect(find.text('VETERAN'), findsWidgets);
        expect(find.text('MEDUSA'), findsWidgets);
        // The other tab.
        await t.tap(find.text('RECENT MATCHES'));
        await t.pump(const Duration(milliseconds: 500));
        expect(find.text('VICTORY'), findsOneWidget);
        expect(find.text('+14'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('a new player has an empty, unranked profile', (t) async {
        await boot(t, size, home: const MenuScreen());
        await t.pump(const Duration(seconds: 1));
        await t.tap(find.textContaining('TESTER'));
        await t.pump(const Duration(seconds: 1));
        expect(find.byType(PlayerProfileModal), findsOneWidget);
        expect(find.text('UNRANKED'), findsOneWidget);
        expect(find.text('No games yet'), findsNWidgets(2));
        expect(t.takeException(), isNull);
      });

      testWidgets('the invite dialog shows who is challenging and counts down', (t) async {
        var accepted = false;
        await boot(t, size, home: const MenuScreen());
        await t.pump(const Duration(seconds: 1));
        final ctx = t.element(find.byType(MenuScreen));
        InviteBannerDialog.show(
          ctx,
          invite: MatchInvite(
            fromId: 'a',
            fromName: 'Alpha',
            toId: 'me',
            lobbyId: 'L1',
            lobbyName: 'Alpha vs Me',
            expiresAt: DateTime.now().add(const Duration(seconds: 60)),
            fromStats: stats(mmr: 1320),
          ),
          onAccept: () => accepted = true,
          onDecline: () {},
        );
        await t.pump(const Duration(seconds: 2));
        expect(find.text('MATCH INVITATION'), findsOneWidget);
        expect(find.text('ALPHA'), findsOneWidget);
        expect(find.text('CHAMPION'), findsOneWidget);
        await t.tap(find.text('ACCEPT'));
        await t.pump(const Duration(seconds: 1));
        expect(accepted, isTrue);
        expect(find.text('MATCH INVITATION'), findsNothing);
        expect(t.takeException(), isNull);
      });
    });
  }

  group('invites', () {
    MatchInvite incoming() => MatchInvite(fromId: 'a', fromName: 'Alpha', toId: 'me', lobbyId: 'L', lobbyName: 'x', expiresAt: DateTime.now().add(const Duration(seconds: 60)));

    testWidgets('Decline removes the invite from any screen', (t) async {
      await boot(t, phone, home: const MenuScreen());
      await t.pump(const Duration(seconds: 1));
      OnlinePresenceService.instance.debugReceiveInvite(incoming());
      await t.pump(const Duration(seconds: 1));
      expect(find.text('MATCH INVITATION'), findsOneWidget);
      await t.tap(find.text('DECLINE'));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('MATCH INVITATION'), findsNothing);
      // The next invite is shown again.
      OnlinePresenceService.instance.debugReceiveInvite(MatchInvite(fromId: 'b', fromName: 'Bravo', toId: 'me', lobbyId: 'L2', lobbyName: 'y', expiresAt: DateTime.now().add(const Duration(seconds: 60))));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('BRAVO'), findsOneWidget);
    });

    testWidgets('Decline removes the dialog even when another route has been pushed above it', (t) async {
      await boot(t, phone, home: const MenuScreen());
      await t.pump(const Duration(seconds: 1));
      OnlinePresenceService.instance.debugReceiveInvite(incoming());
      await t.pump(const Duration(seconds: 1));
      // A screen change on top of the invite (a see-through route, so the dialog stays tappable).
      final nav = Navigator.of(t.element(find.byType(MenuScreen)));
      nav.push(PageRouteBuilder<void>(opaque: false, pageBuilder: (_, _, _) => const IgnorePointer(child: SizedBox.expand())));
      await t.pump(const Duration(seconds: 1));
      // (Pressed directly: the route above has its own barrier.)
      t.widget<PlateButton>(find.widgetWithText(PlateButton, 'DECLINE')).onPressed!();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('MATCH INVITATION'), findsNothing);
      expect(find.byType(MenuScreen), findsOneWidget);
    });
  });

  group('ratings and win-rate books', () {
    test('PvP moves the MMR, PvE never does', () {
      final s = ProfileStats.instance;
      final before = s.mmr;
      s.recordMatch(won: true, heroId: 'medusa', opponentName: 'AI', opponentHeroId: 'alice', mapId: 'm', mode: 'local');
      expect(s.mmr, before);
      expect(s.pve.wins, 1);
      expect(s.pvp.matches, 0);
      final gain = s.recordMatch(won: true, heroId: 'medusa', opponentName: 'Bob', opponentHeroId: 'alice', mapId: 'm', mode: 'online', pvp: true, opponentMmr: 1000);
      expect(gain, 20); // first matches are provisional (K = 40), an even match
      expect(s.mmr, before + 20);
      expect(s.pvp.wins, 1);
      final loss = s.recordMatch(won: false, heroId: 'medusa', opponentName: 'Bob', opponentHeroId: 'alice', mapId: 'm', mode: 'online', pvp: true, opponentMmr: 1000);
      expect(loss, lessThan(0));
      expect(s.profile.pvp.matches, 2);
      expect(s.profile.pve.matches, 1);
    });

    test('an older payload without the split reads as AI matches', () {
      final p = PlayerProfile.fromPayload({'totalMatches': 5, 'wins': 3, 'losses': 2});
      expect(p.pve.wins, 3);
      expect(p.pvp.matches, 0);
      expect(p.ranked, isFalse);
      expect(PlayerProfile.fromPayload({'pvp': 'garbage', 'top5': 7}).mmr, Mmr.start);
    });

    test('the Active Players list puts open lobbies first, then the strongest', () {
      final sorted = ActivePlayersDrawer.sorted([
        user('1', 'Idle low', 'idle', stats: stats(mmr: 900)),
        user('2', 'Playing', 'inGame', stats: stats(mmr: 2000)),
        user('3', 'Idle high', 'idle', stats: stats(mmr: 1500)),
        user('4', 'Matching', 'matching'),
      ]);
      expect([for (final u in sorted) u.id], ['4', '3', '1', '2']);
    });
  });
}
