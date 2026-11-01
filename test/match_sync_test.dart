// Offline match cache and auto sync: every match is saved locally first; pending matches are
// pushed oldest first when online and signed in; a retry can never count a match twice; a match is
// never removed until the server confirmed it; failures retry with a growing delay.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unmatched_game/net/match_record.dart';
import 'package:unmatched_game/net/match_store.dart';
import 'package:unmatched_game/net/match_sync.dart';
import 'package:unmatched_game/net/uuid.dart';

int _n = 0;

MatchRecord rec({
  String? id,
  MatchMode mode = MatchMode.ai,
  DateTime? at,
  bool won = true,
  String? opp,
  int players = 2,
  String hero = 'alice',
}) => MatchRecord(
  matchId: id ?? uuidFromText('match ${++_n}'),
  mode: mode,
  myHero: hero,
  opponentHero: 'medusa',
  opponentName: mode == MatchMode.ai ? 'AI Hard' : 'Bob',
  won: won,
  playedAt: at ?? DateTime.utc(2026, 10, 30, 12, _n),
  durationSeconds: 600,
  opponentUserId: opp,
  players: players,
);

/// A server that behaves like supabase/match_sync.sql for the parts the client depends on: one result
/// per match_id, a repeat returns the stored result, impossible data is rejected.
class FakeServer implements MatchBackend {
  final stored = <String, Map<String, Object?>>{};
  final log = <String>[]; // match ids in the order they were sent
  var calls = 0;
  var down = false;
  var tokenOk = true;
  var rejectIds = <String>{};

  /// Applies the answer on the server but "loses" the reply: the device sees a network error.
  var loseReplyFor = <String>{};
  final counted = <String>[];
  Map<String, Object?> profileJson = {'mmr': 1000, 'peak_mmr': 1000, 'ranked_matches': 0};
  Map<String, Object?>? meJson = {'id': 'acct-1', 'username': 'me'};
  final statusOverride = <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>> submit(String token, Map<String, Object?> m) async {
    calls++;
    if (down) throw const SyncNetworkError('offline');
    if (!tokenOk) throw const SyncAuthError();
    final id = m['match_id'] as String;
    log.add(id);
    if (rejectIds.contains(id)) return {'status': 'rejected', 'reason': 'bad_duration'};
    final dup = stored.containsKey(id);
    final result = stored.putIfAbsent(id, () {
      counted.add(id);
      final ranked = m['mode'] != 'AI' && m['opponent_user_id'] != null && m['players'] == 2;
      return {'status': 'ok', 'match_id': id, 'result': ranked ? 'awaiting_opponent' : 'recorded', 'mmr_before': null, 'mmr_after': null, 'mmr_delta': 0};
    });
    final reply = {...result, 'duplicate': dup};
    if (loseReplyFor.remove(id)) throw const SyncNetworkError('connection lost');
    return reply;
  }

  @override
  Future<List<Map<String, Object?>>> statuses(String token, List<String> ids) async {
    if (down) throw const SyncNetworkError('offline');
    return [
      for (final id in ids)
        if (statusOverride[id] != null) {'match_id': id, ...statusOverride[id]!},
    ];
  }

  @override
  Future<Map<String, Object?>?> me(String token) async {
    if (down) throw const SyncNetworkError('offline');
    return meJson;
  }

  @override
  Future<Map<String, Object?>?> profile(String token) async {
    if (down) throw const SyncNetworkError('offline');
    return profileJson;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MatchRecord', () {
    test('saves and reads back every field', () {
      final r = rec(mode: MatchMode.lan, opp: 'u-2')
        ..myUserId = 'u-1'
        ..syncStatus = SyncStatus.synced
        ..serverResult = 'counted'
        ..mmrBefore = 1000
        ..mmrAfter = 1024
        ..mmrDelta = 24
        ..attempts = 3
        ..lastError = 'x';
      final back = MatchRecord.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(back.toJson(), r.toJson());
      expect(back.playedAt.isUtc, isTrue);
    });

    test('has everything a match record must have', () {
      final j = rec(mode: MatchMode.online, opp: 'u-2').toJson();
      for (final k in ['match_id', 'mode', 'my_user_id', 'opponent_user_id', 'my_hero', 'opponent_hero', 'won', 'played_at', 'duration_s', 'sync_status']) {
        expect(j.containsKey(k), isTrue, reason: k);
      }
      expect(uuidPattern.hasMatch(j['match_id'] as String), isTrue);
      expect(j['sync_status'], 'pending');
    });

    test('the submission is what the server takes', () {
      final s = (rec(mode: MatchMode.lan, opp: 'u-2', won: false)..myUserId = 'u-1').toSubmission();
      expect(s['mode'], 'LAN');
      expect(s['winner'], 'opponent');
      expect(s['opponent_user_id'], 'u-2');
      expect(s['players'], 2);
      expect((s['played_at'] as String).endsWith('Z'), isTrue);
      expect(s['duration_s'], 600);
    });

    test('damaged entries are skipped, never fatal', () {
      expect(MatchRecord.fromJson(null), isNull);
      expect(MatchRecord.fromJson({'match_id': '', 'played_at': 'x'}), isNull);
      expect(MatchRecord.fromJson({'match_id': 'a', 'played_at': 'not a date'}), isNull);
      expect(MatchRecord.fromJson({'match_id': 'a', 'played_at': '2026-10-30T12:00:00Z'}), isNotNull);
    });

    test('what kind of match it was: AI, LAN or online, and when it can be ranked', () {
      MatchRecord f({required int humans, int players = 2, bool online = false, String? opp = 'u-2', String? me = 'u-1'}) => MatchRecord.finished(
        matchId: uuidFromText('x'),
        won: true,
        myHero: 'alice',
        opponentHero: 'medusa',
        opponentName: 'Bob',
        players: players,
        humanOpponents: humans,
        online: online,
        mapId: 'blossom',
        playedAt: DateTime.now(),
        durationSeconds: 300,
        myUserId: me,
        opponentUserId: opp,
      );
      final ai = f(humans: 0, online: true);
      expect(ai.mode, MatchMode.ai, reason: 'only AI seats, even in an online lobby');
      expect(ai.opponentUserId, isNull);
      expect(ai.rankedCandidate, isFalse);
      final lan = f(humans: 1);
      expect(lan.mode, MatchMode.lan);
      expect(lan.opponentUserId, 'u-2');
      expect(lan.rankedCandidate, isTrue);
      expect(f(humans: 1, online: true).mode, MatchMode.online);
      expect(f(humans: 1, opp: null).rankedCandidate, isFalse, reason: 'a guest without an account');
      expect(f(humans: 1, opp: '').opponentUserId, isNull);
      expect(f(humans: 1, players: 4).rankedCandidate, isFalse, reason: 'team games are never ranked');
      expect(f(humans: 2, players: 4).opponentUserId, isNull);
      expect(f(humans: 1, opp: 'u-1').opponentUserId, isNull, reason: 'the same player on both sides');
      expect(f(humans: 1, me: '').myUserId, isNull);
    });
  });

  group('MatchStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a saved match survives a restart (saved before anything else happens)', () async {
      final prefs = await SharedPreferences.getInstance();
      final a = await MatchStore.load(prefs);
      final r = rec();
      expect(await a.add(r), isTrue);
      // The "restart": a fresh store over the same storage.
      final b = await MatchStore.load(await SharedPreferences.getInstance());
      expect(b.length, 1);
      expect(b[r.matchId]!.toJson(), r.toJson());
      expect(b.pendingCount, 1);
    });

    test('the same match_id is never added twice', () async {
      final s = MatchStore.memory();
      final r = rec();
      expect(await s.add(r), isTrue);
      expect(await s.add(rec(id: r.matchId, won: false)), isFalse);
      expect(s.length, 1);
      expect(s[r.matchId]!.won, isTrue);
    });

    test('pending is oldest first by played_at, history is newest first', () async {
      final s = MatchStore.memory();
      final late = rec(at: DateTime.utc(2026, 10, 30, 15));
      final early = rec(at: DateTime.utc(2026, 10, 30, 9));
      final mid = rec(at: DateTime.utc(2026, 10, 30, 12));
      for (final r in [late, early, mid]) {
        await s.add(r);
      }
      expect([for (final r in s.pending) r.matchId], [early.matchId, mid.matchId, late.matchId]);
      expect([for (final r in s.all) r.matchId], [late.matchId, mid.matchId, early.matchId]);
    });

    test('only confirmed matches are ever trimmed; pending and failed ones stay forever', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await MatchStore.load(await SharedPreferences.getInstance());
      final keep = <String>[];
      for (var i = 0; i < MatchStore.keepSynced + 20; i++) {
        final r = rec(at: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)))..syncStatus = SyncStatus.synced;
        await s.add(r);
      }
      final pending = rec(at: DateTime.utc(2020, 1, 1));
      final failed = rec(at: DateTime.utc(2020, 1, 2))..syncStatus = SyncStatus.failed;
      final awaiting = rec(at: DateTime.utc(2020, 1, 3))
        ..syncStatus = SyncStatus.synced
        ..serverResult = 'awaiting_opponent';
      for (final r in [pending, failed, awaiting]) {
        await s.add(r);
        keep.add(r.matchId);
      }
      expect(s.length, MatchStore.keepSynced + 3);
      for (final id in keep) {
        expect(s[id], isNotNull, reason: 'an unconfirmed match was dropped');
      }
    });

    test('a damaged save is ignored, the app starts empty', () async {
      SharedPreferences.setMockInitialValues({'match_records_v1': '{not json'});
      final s = await MatchStore.load(await SharedPreferences.getInstance());
      expect(s.length, 0);
      SharedPreferences.setMockInitialValues({
        'match_records_v1': jsonEncode([rec().toJson(), 5, 'x', {'match_id': 1}]),
      });
      final t = await MatchStore.load(await SharedPreferences.getInstance());
      expect(t.length, 1, reason: 'the good one is kept');
    });
  });

  group('sync', () {
    late MatchStore store;
    late FakeServer server;
    var token = 'tok';
    var accountId = '';
    Map<String, Object?>? shownProfile;

    MatchSyncService make({Stream<bool>? net, math.Random? rng}) => MatchSyncService(
      store: store,
      backend: server,
      token: () => token,
      accountId: () => accountId,
      onAccountId: (id) => accountId = id,
      onProfile: (p) => shownProfile = p,
      connectivity: net,
      random: rng ?? math.Random(1),
    );

    setUp(() {
      store = MatchStore.memory();
      server = FakeServer();
      token = 'tok';
      accountId = '';
      shownProfile = null;
    });

    test('pending matches are sent oldest first, then marked synced', () async {
      final late = rec(at: DateTime.utc(2026, 10, 30, 15));
      final early = rec(at: DateTime.utc(2026, 10, 30, 9));
      final mid = rec(at: DateTime.utc(2026, 10, 30, 12));
      for (final r in [late, early, mid]) {
        await store.add(r);
      }
      final s = make();
      await s.syncNow();
      expect(server.log, [early.matchId, mid.matchId, late.matchId]);
      expect(store.pendingCount, 0);
      expect(store.all.every((r) => r.syncStatus == SyncStatus.synced), isTrue);
      expect(s.state, SyncState.idle);
      expect(s.summary, 'All synced');
      s.dispose();
    });

    test('the server\'s answer is saved: result and rating change', () async {
      final r = rec(mode: MatchMode.lan, opp: 'u-2');
      await store.add(r);
      final s = make();
      await s.syncNow();
      expect(store[r.matchId]!.serverResult, 'awaiting_opponent');
      expect(store[r.matchId]!.ratingLabel, 'Awaiting opponent');
      expect(store[r.matchId]!.mmrDelta, 0);
      s.dispose();
    });

    test('offline: the match stays pending, with the reason, and is kept for the next try', () async {
      final r = rec();
      await store.add(r);
      server.down = true;
      final s = make();
      await s.syncNow();
      expect(store[r.matchId]!.syncStatus, SyncStatus.pending);
      expect(store[r.matchId]!.attempts, 1);
      expect(store[r.matchId]!.lastError, 'offline');
      expect(s.state, SyncState.offline);
      expect(s.summary, 'Offline · 1 match waiting to sync');
      expect(store.length, 1, reason: 'never deleted');
      // The network is back.
      server.down = false;
      await s.syncNow();
      expect(store[r.matchId]!.syncStatus, SyncStatus.synced);
      expect(s.failures, 0);
      s.dispose();
    });

    test('a lost reply cannot count a match twice: the retry gets the stored result', () async {
      final r = rec(mode: MatchMode.lan, opp: 'u-2');
      await store.add(r);
      server.loseReplyFor.add(r.matchId); // the server stored it, the phone never heard
      final s = make();
      await s.syncNow();
      expect(store[r.matchId]!.syncStatus, SyncStatus.pending, reason: 'not confirmed, so still pending');
      await s.syncNow();
      expect(store[r.matchId]!.syncStatus, SyncStatus.synced);
      expect(server.counted, [r.matchId], reason: 'counted once on the server');
      expect(server.calls, 2);
      // Syncing a third time sends nothing at all.
      await s.syncNow();
      expect(server.calls, 2);
      s.dispose();
    });

    test('a failure in the middle keeps the rest pending and in order; nothing is skipped', () async {
      final rs = [for (var i = 0; i < 4; i++) rec(at: DateTime.utc(2026, 10, 30, 9 + i))];
      for (final r in rs.reversed) {
        await store.add(r);
      }
      server.loseReplyFor.add(rs[1].matchId);
      final s = make();
      await s.syncNow();
      expect([for (final r in rs) store[r.matchId]!.syncStatus], [SyncStatus.synced, SyncStatus.pending, SyncStatus.pending, SyncStatus.pending]);
      expect(server.log, [rs[0].matchId, rs[1].matchId], reason: 'it stopped at the first failure');
      await s.syncNow();
      expect(store.pendingCount, 0);
      expect(server.counted.toSet().length, 4);
      expect(server.counted.length, 4, reason: 'each counted exactly once');
      s.dispose();
    });

    test('data the server rejects is kept as failed and never retried', () async {
      final bad = rec();
      final good = rec();
      await store.add(bad);
      await store.add(good);
      server.rejectIds.add(bad.matchId);
      final s = make();
      await s.syncNow();
      expect(store[bad.matchId]!.syncStatus, SyncStatus.failed);
      expect(store[bad.matchId]!.lastError, contains('bad_duration'));
      expect(store[good.matchId]!.syncStatus, SyncStatus.synced);
      expect(store.length, 2, reason: 'a rejected match is still on the device');
      final calls = server.calls;
      await s.syncNow();
      expect(server.calls, calls, reason: 'failed ones are not retried');
      expect(s.summary, '1 match could not be synced');
      s.dispose();
    });

    test('signed out: nothing is sent and everything waits; signing in sends it', () async {
      final r = rec();
      await store.add(r);
      token = '';
      final s = make();
      await s.syncNow();
      expect(server.calls, 0);
      expect(s.state, SyncState.signedOut);
      expect(s.summary, 'Sign in to sync · 1 match waiting to sync');
      expect(store[r.matchId]!.syncStatus, SyncStatus.pending);
      token = 'tok';
      s.nudge();
      await pumpEventQueue();
      expect(store[r.matchId]!.syncStatus, SyncStatus.synced);
      s.dispose();
    });

    test('a session that expired mid-way keeps matches pending without counting it as offline', () async {
      final r = rec();
      await store.add(r);
      server.tokenOk = false;
      final s = make();
      await s.syncNow();
      expect(s.state, SyncState.signedOut);
      expect(s.failures, 0);
      expect(store[r.matchId]!.syncStatus, SyncStatus.pending);
      s.dispose();
    });

    test('your account id is fetched and stamped on records that did not have it', () async {
      final r = rec();
      await store.add(r);
      final s = make();
      await s.syncNow();
      expect(accountId, 'acct-1');
      expect(store[r.matchId]!.myUserId, 'acct-1');
      s.dispose();
    });

    test('after a sync the online profile is handed over (it updates the rating shown)', () async {
      await store.add(rec());
      server.profileJson = {'mmr': 1024, 'peak_mmr': 1024, 'ranked_matches': 1};
      final s = make();
      await s.syncNow();
      expect(shownProfile!['mmr'], 1024);
      s.dispose();
    });

    test('two syncs at once send each match once', () async {
      for (var i = 0; i < 3; i++) {
        await store.add(rec());
      }
      final s = make();
      await Future.wait([s.syncNow(), s.syncNow(), s.syncNow()]);
      await pumpEventQueue();
      expect(server.counted.length, 3);
      expect(server.calls, 3);
      s.dispose();
    });

    test('a match waiting for the opponent is refreshed to counted, with its rating change', () async {
      final r = rec(mode: MatchMode.lan, opp: 'u-2');
      await store.add(r);
      final s = make();
      await s.syncNow();
      expect(store[r.matchId]!.serverResult, 'awaiting_opponent');
      server.statusOverride[r.matchId] = {'result': 'counted', 'mmr_before': 1000, 'mmr_after': 1024, 'mmr_delta': 24};
      await s.syncNow();
      expect(store[r.matchId]!.serverResult, 'counted');
      expect(store[r.matchId]!.mmrDelta, 24);
      expect(store[r.matchId]!.mmrAfter, 1024);
      expect(store[r.matchId]!.ratingLabel, '+24 MMR');
      s.dispose();
    });

    test('summary: nothing yet, waiting, offline, all synced', () async {
      final s = make();
      expect(s.summary, 'No matches yet');
      await store.add(rec());
      expect(s.summary, '1 match waiting to sync');
      await store.add(rec());
      expect(s.summary, '2 matches waiting to sync');
      await s.syncNow();
      expect(s.summary, 'All synced');
      s.dispose();
    });

    test('without a server (offline build) matches just stay saved and nothing is scheduled', () async {
      await store.add(rec());
      final s = MatchSyncService(store: store, backend: const NoBackend(), token: () => 'tok');
      await s.syncNow();
      s.matchSaved();
      await pumpEventQueue();
      expect(store.pendingCount, 1);
      expect(s.state, SyncState.idle);
      s.dispose();
    });

    test('backoff doubles from 5 s up to 15 minutes, with a little jitter', () {
      final s = make();
      for (var f = 1; f <= 12; f++) {
        final nominal = math.min(15 * 60 * 1000.0, 5000 * math.pow(2, f - 1));
        for (var i = 0; i < 20; i++) {
          final d = s.delayAfter(f).inMilliseconds;
          expect(d, greaterThanOrEqualTo((nominal * 0.75).round()), reason: 'failure $f');
          expect(d, lessThanOrEqualTo(15 * 60 * 1000), reason: 'never longer than the cap');
          expect(d, lessThanOrEqualTo((nominal * 1.25).round()), reason: 'failure $f');
        }
      }
      expect(s.delayAfter(0), const Duration(seconds: 5));
      s.dispose();
    });
  });

  group('sync over time', () {
    testWidgets('a failed attempt is retried by itself with growing delays, then succeeds when the network is back', (t) async {
      final store = MatchStore.memory();
      final server = FakeServer()..down = true;
      final r = rec();
      await store.add(r);
      final s = MatchSyncService(
        store: store,
        backend: server,
        token: () => 'tok',
        accountId: () => 'acct-1',
        random: math.Random(7),
      );
      s.matchSaved();
      await t.pump();
      expect(server.calls, 1);
      expect(s.state, SyncState.offline);
      // The retries come on their own, further and further apart.
      var last = server.calls;
      final gaps = <int>[];
      var waited = 0;
      for (var ms = 0; ms < 120000 && gaps.length < 4; ms += 500) {
        await t.pump(const Duration(milliseconds: 500));
        waited += 500;
        if (server.calls != last) {
          gaps.add(waited);
          waited = 0;
          last = server.calls;
        }
      }
      expect(gaps.length, 4);
      for (var i = 1; i < gaps.length; i++) {
        expect(gaps[i], greaterThan(gaps[i - 1] * 1.3), reason: 'the delay grows: $gaps');
      }
      expect(store[r.matchId]!.syncStatus, SyncStatus.pending);
      // Back online: the next retry delivers it.
      server.down = false;
      for (var ms = 0; ms < 120000 && store.pendingCount > 0; ms += 1000) {
        await t.pump(const Duration(seconds: 1));
      }
      expect(store[r.matchId]!.syncStatus, SyncStatus.synced);
      expect(s.state, SyncState.idle);
      // Nothing is scheduled any more.
      final calls = server.calls;
      await t.pump(const Duration(minutes: 20));
      expect(server.calls, calls);
      s.dispose();
    });

    testWidgets('a "network is back" signal syncs at once, without waiting for the retry timer', (t) async {
      final store = MatchStore.memory();
      final server = FakeServer()..down = true;
      await store.add(rec());
      final net = StreamController<bool>.broadcast();
      final s = MatchSyncService(store: store, backend: server, token: () => 'tok', accountId: () => 'a', connectivity: net.stream, random: math.Random(1));
      await s.syncNow();
      expect(store.pendingCount, 1);
      server.down = false;
      net.add(false);
      await t.pump();
      expect(store.pendingCount, 1, reason: 'a signal that says offline does nothing');
      net.add(true);
      await t.pump();
      await t.pump();
      expect(store.pendingCount, 0);
      s.dispose();
      await net.close();
    });

    testWidgets('a match waiting for its opponent is looked at again every minute', (t) async {
      final store = MatchStore.memory();
      final server = FakeServer();
      final r = rec(mode: MatchMode.online, opp: 'u-2');
      await store.add(r);
      final s = MatchSyncService(store: store, backend: server, token: () => 'tok', accountId: () => 'a', random: math.Random(1));
      s.matchSaved();
      await t.pump();
      expect(store[r.matchId]!.serverResult, 'awaiting_opponent');
      server.statusOverride[r.matchId] = {'result': 'counted', 'mmr_before': 1000, 'mmr_after': 976, 'mmr_delta': -24};
      await t.pump(const Duration(seconds: 61));
      await t.pump();
      expect(store[r.matchId]!.serverResult, 'counted');
      expect(store[r.matchId]!.mmrDelta, -24);
      // Once counted nothing more is scheduled.
      final calls = server.calls;
      await t.pump(const Duration(minutes: 5));
      expect(server.calls, calls);
      s.dispose();
    });
  });

  group('contract with supabase/match_sync.sql', () {
    // The exact payload the app sends. tool/sql_test/run.mjs submits this same file to the SQL
    // function, so the two can't drift apart. Run with --dart-define=UPDATE_FIXTURE=true to rewrite it.
    test('the submission matches the fixture the SQL tests use', () {
      final r = MatchRecord.finished(
        matchId: '11111111-2222-4333-8444-555555555555',
        won: true,
        myHero: 'alice',
        opponentHero: 'medusa',
        opponentName: 'Bob',
        players: 2,
        humanOpponents: 1,
        online: false,
        mapId: 'blossom',
        playedAt: DateTime.utc(2026, 10, 30, 12),
        durationSeconds: 600,
        myUserId: '00000000-0000-4000-8000-000000000001',
        opponentUserId: '00000000-0000-4000-8000-000000000002',
      );
      final file = File('tool/sql_test/sample_submission.json');
      final now = const JsonEncoder.withIndent('  ').convert(r.toSubmission());
      if (const bool.fromEnvironment('UPDATE_FIXTURE') || !file.existsSync()) {
        file.writeAsStringSync('$now\n');
      }
      expect(jsonDecode(file.readAsStringSync()), jsonDecode(now), reason: 'the payload changed: update the SQL or the fixture');
    });
  });

  group('ids', () {
    test('a random uuid looks like one, and they differ', () {
      final a = newUuid(), b = newUuid();
      expect(uuidPattern.hasMatch(a), isTrue);
      expect(a, isNot(b));
    });
    test('an id worked out from text is the same every time and for different text differs', () {
      expect(uuidFromText('1|a,b|blossom'), uuidFromText('1|a,b|blossom'));
      expect(uuidFromText('1|a,b|blossom'), isNot(uuidFromText('2|a,b|blossom')));
      expect(uuidPattern.hasMatch(uuidFromText('anything')), isTrue);
    });
  });
}
