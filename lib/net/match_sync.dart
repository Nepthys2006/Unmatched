/// Pushes the matches saved on this device to the server, safely.
///
/// * Matches are sent oldest first (by `played_at`), one at a time.
/// * The server decides; a match leaves "pending" only when the server said it has it. A network
///   error, a timeout or a signed-out session leaves it pending and is retried with a growing delay
///   (5 s, 10 s, 20 s ... at most 15 minutes, with a little jitter). Nothing is ever deleted here.
/// * Sending is idempotent: the server keeps one result per (match_id, player) and returns it
///   again for a repeat, so a retry after a lost answer cannot count a match twice.
/// * Being online is noticed by trying: every attempt that reaches the server clears the "offline"
///   state, and attempts are also made when the app starts, resumes, signs in, finishes a match, or a
///   platform connectivity signal (see [MatchSyncService.connectivity]) says the network is back.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import 'match_record.dart';
import 'match_store.dart';
import 'online.dart' show isOnlineConfigured, newSupabaseClient;

/// The server could not be reached (or answered with something unusable): try again later.
class SyncNetworkError implements Exception {
  const SyncNetworkError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The session token is not (or no longer) valid: matches stay pending until the player signs in.
class SyncAuthError implements Exception {
  const SyncAuthError();
  @override
  String toString() => 'Signed out';
}

/// What the sync needs from the server (a fake in tests, Supabase in the app).
abstract class MatchBackend {
  /// `{status:'ok', result, mmr_before, mmr_after, mmr_delta, duplicate}` or `{status:'rejected', reason}`.
  Future<Map<String, Object?>> submit(String token, Map<String, Object?> match);

  /// Current result and rating change of some of this player's matches.
  Future<List<Map<String, Object?>>> statuses(String token, List<String> matchIds);

  /// The account id and username of a token, or null.
  Future<Map<String, Object?>?> me(String token);

  /// The online profile (rating, records, heroes) of a token.
  Future<Map<String, Object?>?> profile(String token);
}

/// A backend that is never there: offline play, and tests that don't care about syncing.
class NoBackend implements MatchBackend {
  const NoBackend();
  Never _no() => throw const SyncNetworkError('Online play is not configured.');
  @override
  Future<Map<String, Object?>> submit(String token, Map<String, Object?> match) async => _no();
  @override
  Future<List<Map<String, Object?>>> statuses(String token, List<String> matchIds) async => _no();
  @override
  Future<Map<String, Object?>?> me(String token) async => _no();
  @override
  Future<Map<String, Object?>?> profile(String token) async => _no();
}

/// The Supabase functions in supabase/match_sync.sql.
class SupabaseMatchBackend implements MatchBackend {
  SupabaseMatchBackend({SupabaseClient? client}) : _given = client;
  final SupabaseClient? _given;
  SupabaseClient? _made;
  SupabaseClient get _c => _given ?? (_made ??= newSupabaseClient());

  Future<Object?> _call(String fn, Map<String, Object?> params) async {
    if (_given == null && !isOnlineConfigured) {
      throw const SyncNetworkError('Online play is not configured.');
    }
    try {
      return await _c.rpc(fn, params: params).timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      if (e.message.contains('Not signed in')) throw const SyncAuthError();
      if (e.code == 'PGRST202' || e.message.contains('Could not find the function')) {
        throw const SyncNetworkError("Match syncing isn't set up on the server yet.");
      }
      throw SyncNetworkError(e.message);
    } on TimeoutException {
      throw const SyncNetworkError("The server didn't answer.");
    } catch (e) {
      if (e is SyncNetworkError || e is SyncAuthError) rethrow;
      throw const SyncNetworkError("Can't reach the server.");
    }
  }

  Map<String, Object?>? _map(Object? r) => r is Map ? r.cast<String, Object?>() : null;

  @override
  Future<Map<String, Object?>> submit(String token, Map<String, Object?> match) async {
    final r = _map(await _call('submit_match', {'p_token': token, 'p_match': match}));
    if (r == null) throw const SyncNetworkError('Unexpected answer from the server.');
    return r;
  }

  @override
  Future<List<Map<String, Object?>>> statuses(String token, List<String> matchIds) async {
    final r = await _call('get_match_statuses', {'p_token': token, 'p_ids': matchIds});
    return [
      if (r is List)
        for (final x in r)
          if (x is Map) x.cast<String, Object?>(),
    ];
  }

  @override
  Future<Map<String, Object?>?> me(String token) async => _map(await _call('account_me', {'p_token': token}));

  @override
  Future<Map<String, Object?>?> profile(String token) async => _map(await _call('get_my_profile', {'p_token': token}));
}

enum SyncState {
  /// Nothing is being sent.
  idle,

  /// Talking to the server.
  syncing,

  /// The last attempt could not reach the server.
  offline,

  /// Matches are waiting for a signed-in account.
  signedOut,
}

class MatchSyncService extends ChangeNotifier {
  MatchSyncService({
    required this.store,
    required this.backend,
    required this.token,
    this.accountId,
    this.onAccountId,
    this.onProfile,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 15),
    this.pollAwaiting = const Duration(minutes: 1),
    this.connectivity,
    math.Random? random,
  }) : _rng = random ?? math.Random() {
    _link = connectivity?.listen((online) {
      if (online) unawaited(syncNow());
    });
  }

  final MatchStore store;
  final MatchBackend backend;

  /// The signed-in session token (empty when signed out).
  final String Function() token;
  final String? Function()? accountId;

  /// Called with the account id once the server told it.
  final void Function(String id)? onAccountId;

  /// Called with the online profile after a successful sync (it updates the rating shown).
  final void Function(Map<String, Object?> profile)? onProfile;

  final Duration baseDelay;
  final Duration maxDelay;

  /// How often matches that wait for the other player are looked at again.
  final Duration pollAwaiting;

  /// A platform's "network is back" signal (`true` = online), if there is one.
  final Stream<bool>? connectivity;
  StreamSubscription<bool>? _link;
  final math.Random _rng;

  SyncState state = SyncState.idle;
  String? lastError;
  DateTime? lastSyncedAt;
  int _failures = 0;
  bool _running = false;
  bool _again = false;
  Timer? _timer;
  bool _disposed = false;

  bool get signedIn => token().isNotEmpty;
  int get pendingCount => store.pendingCount;
  int get failedCount => store.failedCount;

  /// "3 matches waiting to sync", "All synced", ... for the small indicator.
  String get summary {
    final n = pendingCount;
    final st = signedIn ? state : SyncState.signedOut;
    if (n > 0) {
      final what = '$n match${n == 1 ? '' : 'es'} waiting to sync';
      return switch (st) {
        SyncState.syncing => 'Syncing $n match${n == 1 ? '' : 'es'}…',
        SyncState.offline => 'Offline · $what',
        SyncState.signedOut => 'Sign in to sync · $what',
        SyncState.idle => what,
      };
    }
    if (state == SyncState.syncing) return 'Syncing…';
    if (failedCount > 0) return '$failedCount match${failedCount == 1 ? '' : 'es'} could not be synced';
    if (store.length == 0) return 'No matches yet';
    if (!signedIn) return 'Sign in to sync your matches';
    return st == SyncState.offline ? 'Offline · all saved' : 'All synced';
  }

  /// The wait before the next attempt after [failures] failures in a row.
  Duration delayAfter(int failures) {
    if (failures <= 0) return baseDelay;
    final ms = math.min(maxDelay.inMilliseconds.toDouble(), baseDelay.inMilliseconds * math.pow(2, failures - 1));
    return Duration(milliseconds: (ms * (0.75 + _rng.nextDouble() * 0.5)).round().clamp(1, maxDelay.inMilliseconds));
  }

  @visibleForTesting
  int get failures => _failures;

  /// Sends what is pending, now. Safe to call at any time and as often as you like.
  Future<void> syncNow() async {
    if (_disposed) return;
    // No server to talk to (offline builds, tests): matches simply stay saved on the device.
    if (backend is NoBackend) return;
    if (_running) {
      _again = true;
      return;
    }
    if (!signedIn) {
      _set(SyncState.signedOut);
      return;
    }
    _running = true;
    _timer?.cancel();
    _set(SyncState.syncing);
    try {
      await _identity();
      for (final r in store.pending) {
        final mine = accountId?.call();
        if (r.myUserId == null && mine != null && mine.isNotEmpty) r.myUserId = mine;
        // A network error stops here (the rest would fail the same way); the matches stay pending.
        final res = await backend.submit(token(), r.toSubmission());
        await _apply(r, res);
      }
      await _refreshAwaiting();
      await _pullProfile();
      _failures = 0;
      lastError = null;
      lastSyncedAt = DateTime.now();
      _set(SyncState.idle);
    } on SyncNetworkError catch (e) {
      _failures++;
      lastError = e.message;
      await _noteFailedAttempt(e.message);
      _set(SyncState.offline);
    } on SyncAuthError {
      lastError = 'Your session expired. Sign in again to sync.';
      _set(SyncState.signedOut);
    } catch (e) {
      // Anything unexpected is treated like a network problem: the matches stay pending.
      _failures++;
      lastError = '$e';
      _set(SyncState.offline);
    } finally {
      _running = false;
      if (_again && !_disposed) {
        _again = false;
        _schedule(immediately: true);
      } else {
        _schedule();
      }
    }
  }

  /// Every match still waiting remembers that an attempt failed, and why (it stays pending).
  Future<void> _noteFailedAttempt(String why) async {
    for (final r in store.pending) {
      r.attempts++;
      r.lastError = why;
      await store.update(r);
    }
  }

  Future<void> _identity() async {
    if ((accountId?.call() ?? '').isNotEmpty) return;
    final me = await backend.me(token());
    final id = me?['id'];
    if (id is String && id.isNotEmpty) onAccountId?.call(id);
  }

  Future<void> _apply(MatchRecord r, Map<String, Object?> res) async {
    if (res['status'] == 'rejected') {
      // Data that can never be valid: kept (never deleted) but not retried.
      r.syncStatus = SyncStatus.failed;
      r.lastError = 'Rejected by the server: ${res['reason']}';
    } else {
      r.syncStatus = SyncStatus.synced;
      r.serverResult = res['result'] as String?;
      r.mmrBefore = (res['mmr_before'] as num?)?.toInt();
      r.mmrAfter = (res['mmr_after'] as num?)?.toInt();
      r.mmrDelta = (res['mmr_delta'] as num?)?.toInt() ?? 0;
      r.lastError = null;
    }
    await store.update(r);
  }

  /// Matches the other player had not sent yet may have been rated since.
  Future<void> _refreshAwaiting() async {
    final waiting = store.awaitingOpponent;
    if (waiting.isEmpty) return;
    final rows = await backend.statuses(token(), [for (final r in waiting) r.matchId]);
    for (final row in rows) {
      final r = store[row['match_id'] as String? ?? ''];
      if (r == null) continue;
      r.serverResult = row['result'] as String? ?? r.serverResult;
      r.mmrBefore = (row['mmr_before'] as num?)?.toInt() ?? r.mmrBefore;
      r.mmrAfter = (row['mmr_after'] as num?)?.toInt() ?? r.mmrAfter;
      r.mmrDelta = (row['mmr_delta'] as num?)?.toInt() ?? r.mmrDelta;
      await store.update(r);
    }
  }

  Future<void> _pullProfile() async {
    final p = await backend.profile(token());
    if (p != null) onProfile?.call(p);
  }

  void _set(SyncState s) {
    state = s;
    if (!_disposed) notifyListeners();
  }

  /// The next attempt: soon after a failure (growing), now for a fresh match, and slowly while only
  /// waiting for an opponent's copy of a match.
  void _schedule({bool immediately = false}) {
    _timer?.cancel();
    if (_disposed || !signedIn) return;
    if (immediately) {
      _timer = Timer(Duration.zero, () => unawaited(syncNow()));
      return;
    }
    if (store.pendingCount > 0 && state != SyncState.signedOut) {
      _timer = Timer(delayAfter(_failures), () => unawaited(syncNow()));
    } else if (store.awaitingOpponent.isNotEmpty) {
      _timer = Timer(pollAwaiting, () => unawaited(syncNow()));
    }
  }

  /// A match was just saved: send it, and anything else waiting, straight away.
  void matchSaved() {
    _failures = 0;
    unawaited(syncNow());
  }

  /// The app came back, the player signed in, or the network returned: forget the waiting time.
  void nudge() {
    _failures = 0;
    unawaited(syncNow());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_link?.cancel());
    super.dispose();
  }
}
