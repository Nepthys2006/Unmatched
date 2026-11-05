// The Pro AI level on the lobby wire: older builds only know Easy … Insane and must not break.

import 'package:flutter_test/flutter_test.dart';
import 'package:unmatched_game/engine/ai.dart';
import 'package:unmatched_game/net/session.dart';
import 'package:unmatched_game/ui/match/match_config.dart';

Lobby _lobby(AiLevel ai) => Lobby(
  mode: GameMode.duel,
  players: 2,
  mapId: 'sarpedon',
  ai: ai,
  seats: [LobbySeat(SeatKind.human, name: 'Host', host: true), LobbySeat(SeatKind.ai)],
);

void main() {
  test('every level survives a round trip', () {
    for (final l in AiLevel.values) {
      expect(Lobby.fromJson(_lobby(l).toJson()).ai, l);
    }
  });

  test('Pro is sent as Insane in the field older builds read', () {
    final m = _lobby(AiLevel.pro).toJson();
    expect(m['ai'], 'insane');
    expect(AiLevel.values.map((l) => l.name).take(4), contains(m['ai']));
    expect(m['aiLevel'], 'pro');
  });

  test('a lobby from an older build (no aiLevel) still reads', () {
    final m = _lobby(AiLevel.hard).toJson()..remove('aiLevel');
    expect(Lobby.fromJson(m).ai, AiLevel.hard);
  });

  test('a level from a newer build falls back instead of throwing', () {
    final m = _lobby(AiLevel.hard).toJson()..['aiLevel'] = 'grandmaster';
    expect(Lobby.fromJson(m).ai, AiLevel.hard);
    m['ai'] = 'grandmaster';
    expect(Lobby.fromJson(m).ai, AiLevel.insane);
  });
}
