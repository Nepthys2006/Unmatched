/// One finished match as this device saves it, before and after it reaches the server.
///
/// Every finished match is written to local storage first (vs AI, LAN and online alike); the
/// server only ever adds to it. The record is deleted by nothing: a match stays on the device until
/// the server confirmed it (and then only the oldest confirmed ones are trimmed, see MatchStore).
library;

import 'dart:math' as math;

/// How a match was played.
enum MatchMode {
  /// Against the computer only (offline, or AI seats in a lobby).
  ai('AI'),

  /// Over Wi-Fi or a hotspot against other people.
  lan('LAN'),

  /// Over the internet against other people.
  online('ONLINE');

  const MatchMode(this.wire);

  /// What the server calls it.
  final String wire;

  static MatchMode fromWire(Object? v) => values.firstWhere((m) => m.wire == '$v'.toUpperCase(), orElse: () => MatchMode.ai);
}

/// Where a record is on its way to the server.
enum SyncStatus {
  /// Saved here, not confirmed by the server yet (it will be retried).
  pending,

  /// The server has it. Whether it moved the rating is in [MatchRecord.serverResult].
  synced,

  /// The server refused it for good (impossible data): it is kept, never retried.
  failed;

  static SyncStatus fromName(Object? v) => values.firstWhere((s) => s.name == v, orElse: () => SyncStatus.pending);
}

/// How a match ended. Leaving, going AFK or dropping out of a 1 v 1 against another player is a loss
/// for the one who left (and a win for the other), and it rates like any other result.
enum EndedBy {
  normal('normal'),

  /// This player left, ran out of time too often (afk) or lost their connection for good.
  forfeitMe('forfeit_me'),

  /// The other player did.
  forfeitOpponent('forfeit_opponent');

  const EndedBy(this.wire);
  final String wire;

  static EndedBy fromWire(Object? v) => values.firstWhere((e) => e.wire == v, orElse: () => EndedBy.normal);
}

class MatchRecord {
  MatchRecord({
    required this.matchId,
    required this.mode,
    required this.myHero,
    required this.won,
    required this.playedAt,
    required this.durationSeconds,
    this.myUserId,
    this.opponentUserId,
    this.opponentHero = '',
    this.opponentName = '',
    this.players = 2,
    this.mapId = '',
    this.syncStatus = SyncStatus.pending,
    this.attempts = 0,
    this.lastError,
    this.serverResult,
    this.mmrBefore,
    this.mmrAfter,
    this.mmrDelta = 0,
    this.endedBy = EndedBy.normal,
    this.forfeitReason,
    this.turns,
  });

  /// Unique per match; the same on both devices of a LAN or online match.
  final String matchId;
  final MatchMode mode;

  /// The account ids (null: unknown at the time, a guest, or the AI).
  String? myUserId;
  final String? opponentUserId;
  final String myHero;
  final String opponentHero;
  final String opponentName;
  final bool won;

  /// Seats in the match (2 for a duel); only 1 v 1 against another account can be ranked.
  final int players;
  final String mapId;
  final DateTime playedAt;
  final int durationSeconds;

  SyncStatus syncStatus;
  int attempts;
  String? lastError;

  /// What the server decided: recorded, awaiting_opponent, counted, disputed, expired.
  String? serverResult;
  int? mmrBefore;
  int? mmrAfter;

  /// 0 for anything that does not move the rating, and until the server has decided.
  int mmrDelta;

  /// How it ended, and for a forfeit why: `leave`, `afk` or `disconnect`.
  final EndedBy endedBy;
  final String? forfeitReason;

  /// Turns played (the server only believes a one-sided forfeit claim from a real match).
  final int? turns;

  /// One line for the history: who left, if anyone.
  String? get endLabel {
    if (endedBy == EndedBy.normal) return null;
    final mine = endedBy == EndedBy.forfeitMe;
    final how = switch (forfeitReason) {
      'afk' => mine ? 'You were away too long' : 'Opponent was away too long',
      'disconnect' => mine ? 'You lost connection' : 'Opponent lost connection',
      _ => mine ? 'You left the match' : 'Opponent left the match',
    };
    return how;
  }

  /// "me" or "opponent", as the server wants it.
  String get winner => won ? 'me' : 'opponent';

  /// Could this match move MMR at all (two registered players, a duel, over LAN or online)?
  bool get rankedCandidate => mode != MatchMode.ai && opponentUserId != null && players == 2;

  /// The server still waits for the other player (or the server hasn't seen it).
  bool get awaitingOpponent => serverResult == 'awaiting_opponent';

  /// What one line of the history says about the rating.
  String get ratingLabel => switch (serverResult) {
    'counted' => '${mmrDelta >= 0 ? '+' : ''}$mmrDelta MMR',
    'awaiting_opponent' => 'Awaiting opponent',
    'disputed' => 'Disputed',
    'expired' => 'Expired',
    'void' => 'Too short to count',
    'recorded' => 'Not ranked',
    _ => rankedCandidate ? 'Ranked when synced' : 'Not ranked',
  };

  /// The record for a match that just ended. The rules for what kind of match it was:
  /// * no other person in it (offline, or only AI seats in a lobby): [MatchMode.ai];
  /// * otherwise [MatchMode.online] or [MatchMode.lan] by where it was played;
  /// * [opponentUserId] is set only for a 1 v 1 against one other person who has an account, since
  ///   that is the only kind of match that can be ranked.
  factory MatchRecord.finished({
    required String matchId,
    required bool won,
    required String myHero,
    required String opponentHero,
    required String opponentName,
    required int players,
    required int humanOpponents,
    required bool online,
    required String mapId,
    required DateTime playedAt,
    required int durationSeconds,
    String? myUserId,
    String? opponentUserId,
    EndedBy endedBy = EndedBy.normal,
    String? forfeitReason,
    int? turns,
  }) {
    final mode = humanOpponents == 0 ? MatchMode.ai : (online ? MatchMode.online : MatchMode.lan);
    final duel = players == 2 && humanOpponents == 1;
    final mine = myUserId == null || myUserId.isEmpty ? null : myUserId;
    final theirs = opponentUserId == null || opponentUserId.isEmpty ? null : opponentUserId;
    return MatchRecord(
      matchId: matchId,
      mode: mode,
      myUserId: mine,
      opponentUserId: mode == MatchMode.ai || !duel || theirs == mine ? null : theirs,
      myHero: myHero,
      opponentHero: opponentHero,
      opponentName: opponentName,
      won: won,
      players: players,
      mapId: mapId,
      playedAt: playedAt.toUtc(),
      // A match is never shorter than a second on paper; the server sets the real limit.
      durationSeconds: math.max(0, durationSeconds),
      endedBy: mode == MatchMode.ai ? EndedBy.normal : endedBy,
      forfeitReason: mode == MatchMode.ai || endedBy == EndedBy.normal ? null : forfeitReason,
      turns: turns,
    );
  }

  /// The payload `submit_match` takes.
  Map<String, Object?> toSubmission() => {
    'match_id': matchId,
    'mode': mode.wire,
    'my_user_id': myUserId,
    'opponent_user_id': opponentUserId,
    'my_hero': myHero,
    'opponent_hero': opponentHero.isEmpty ? null : opponentHero,
    'winner': winner,
    'played_at': playedAt.toUtc().toIso8601String(),
    'duration_s': durationSeconds,
    'players': players,
    'map_id': mapId.isEmpty ? null : mapId,
    'ended_by': endedBy.wire,
    'forfeit_reason': forfeitReason,
    'turns': turns,
  };

  Map<String, Object?> toJson() => {
    'match_id': matchId,
    'mode': mode.wire,
    'my_user_id': myUserId,
    'opponent_user_id': opponentUserId,
    'my_hero': myHero,
    'opponent_hero': opponentHero,
    'opponent_name': opponentName,
    'won': won,
    'players': players,
    'map_id': mapId,
    'played_at': playedAt.toUtc().toIso8601String(),
    'duration_s': durationSeconds,
    'sync_status': syncStatus.name,
    'attempts': attempts,
    'last_error': lastError,
    'server_result': serverResult,
    'mmr_before': mmrBefore,
    'mmr_after': mmrAfter,
    'mmr_delta': mmrDelta,
    'ended_by': endedBy.wire,
    'forfeit_reason': forfeitReason,
    'turns': turns,
  };

  /// Reads a saved record; null for anything that is not one (a damaged entry is skipped, never fatal).
  static MatchRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final id = j['match_id'];
      final played = DateTime.tryParse('${j['played_at']}');
      if (id is! String || id.isEmpty || played == null) return null;
      return MatchRecord(
        matchId: id,
        mode: MatchMode.fromWire(j['mode']),
        myUserId: j['my_user_id'] as String?,
        opponentUserId: j['opponent_user_id'] as String?,
        myHero: j['my_hero'] as String? ?? '',
        opponentHero: j['opponent_hero'] as String? ?? '',
        opponentName: j['opponent_name'] as String? ?? '',
        won: j['won'] == true,
        players: (j['players'] as num?)?.toInt() ?? 2,
        mapId: j['map_id'] as String? ?? '',
        playedAt: played.toUtc(),
        durationSeconds: (j['duration_s'] as num?)?.toInt() ?? 0,
        syncStatus: SyncStatus.fromName(j['sync_status']),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        lastError: j['last_error'] as String?,
        serverResult: j['server_result'] as String?,
        mmrBefore: (j['mmr_before'] as num?)?.toInt(),
        mmrAfter: (j['mmr_after'] as num?)?.toInt(),
        mmrDelta: (j['mmr_delta'] as num?)?.toInt() ?? 0,
        endedBy: EndedBy.fromWire(j['ended_by']),
        forfeitReason: j['forfeit_reason'] as String?,
        turns: (j['turns'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
