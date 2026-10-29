import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/net/profile_stats.dart';

void main() {
  group('ProfileStats', () {
    test('initial state is empty', () {
      final stats = ProfileStats.instance;
      expect(stats.totalMatches, 0);
      expect(stats.wins, 0);
      expect(stats.losses, 0);
      expect(stats.overallWinRate, 0.0);
      expect(stats.top5Heroes, isEmpty);
      expect(stats.recentMatches, isEmpty);
    });

    test('records match victories and defeats correctly', () {
      final stats = ProfileStats.instance;

      stats.recordMatch(
        won: true,
        heroId: 'medusa',
        opponentName: 'Arthur',
        opponentHeroId: 'king-arthur',
        mapId: 'sarpedon',
        mode: 'duel',
      );

      expect(stats.totalMatches, 1);
      expect(stats.wins, 1);
      expect(stats.losses, 0);
      expect(stats.overallWinRate, 100.0);
      expect(stats.recentMatches.length, 1);
      expect(stats.recentMatches.first.victory, isTrue);
      expect(stats.recentMatches.first.heroId, 'medusa');
      expect(stats.recentMatches.first.opponentName, 'Arthur');

      stats.recordMatch(
        won: false,
        heroId: 'medusa',
        opponentName: 'Sinbad',
        opponentHeroId: 'sinbad',
        mapId: 'sarpedon',
        mode: 'duel',
      );

      expect(stats.totalMatches, 2);
      expect(stats.wins, 1);
      expect(stats.losses, 1);
      expect(stats.overallWinRate, 50.0);
      expect(stats.heroRecords['medusa']!.matches, 2);
      expect(stats.heroRecords['medusa']!.wins, 1);
      expect(stats.heroRecords['medusa']!.losses, 1);
      expect(stats.heroRecords['medusa']!.winRate, 50.0);
    });

    test('top5Heroes ranks by matches and wins descending', () {
      final stats = ProfileStats.instance;

      // Add matches for 6 different heroes
      for (int i = 0; i < 10; i++) {
        stats.recordMatch(won: true, heroId: 'hero_a', opponentName: 'AI', opponentHeroId: 'x', mapId: 'm', mode: 'duel');
      }
      for (int i = 0; i < 8; i++) {
        stats.recordMatch(won: false, heroId: 'hero_b', opponentName: 'AI', opponentHeroId: 'x', mapId: 'm', mode: 'duel');
      }
      for (int i = 0; i < 6; i++) {
        stats.recordMatch(won: true, heroId: 'hero_c', opponentName: 'AI', opponentHeroId: 'x', mapId: 'm', mode: 'duel');
      }
      for (int i = 0; i < 4; i++) {
        stats.recordMatch(won: true, heroId: 'hero_d', opponentName: 'AI', opponentHeroId: 'x', mapId: 'm', mode: 'duel');
      }
      for (int i = 0; i < 2; i++) {
        stats.recordMatch(won: true, heroId: 'hero_e', opponentName: 'AI', opponentHeroId: 'x', mapId: 'm', mode: 'duel');
      }
      // hero_f has only 1 match
      stats.recordMatch(won: true, heroId: 'hero_f', opponentName: 'AI', opponentHeroId: 'x', mapId: 'm', mode: 'duel');

      final top5 = stats.top5Heroes;
      expect(top5.length, 5);
      expect(top5[0].heroId, 'hero_a');
      expect(top5[0].matches, 10);
      expect(top5[1].heroId, 'hero_b');
      expect(top5[1].matches, 8);
      expect(top5[2].heroId, 'hero_c');
      expect(top5[2].matches, 6);
      expect(top5[3].heroId, 'hero_d');
      expect(top5[3].matches, 4);
      expect(top5[4].heroId, 'hero_e');
      expect(top5[4].matches, 2);
    });

    test('summary payload serialization contains all expected keys', () {
      final stats = ProfileStats.instance;
      final payload = stats.toSummaryPayload();

      expect(payload.containsKey('totalMatches'), isTrue);
      expect(payload.containsKey('wins'), isTrue);
      expect(payload.containsKey('losses'), isTrue);
      expect(payload.containsKey('overallWinRate'), isTrue);
      expect(payload.containsKey('top5'), isTrue);
      expect(payload.containsKey('recent'), isTrue);
    });
  });
}
