/// The device's own copy of every finished match. Matches are written here first, whether the
/// device is online or not; nothing is removed until the server has confirmed it.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'match_record.dart';

class MatchStore extends ChangeNotifier {
  MatchStore._(this._prefs) {
    _read();
  }

  /// In memory only (tests, and when storage is unavailable).
  factory MatchStore.memory() => MatchStore._(null);

  static Future<MatchStore> load([SharedPreferences? prefs]) async {
    SharedPreferences? p = prefs;
    if (p == null) {
      try {
        p = await SharedPreferences.getInstance();
      } catch (_) {
        p = null;
      }
    }
    return MatchStore._(p);
  }

  static const _key = 'match_records_v1';

  /// How many confirmed matches are kept for the history. Pending and failed ones are never dropped.
  static const keepSynced = 300;

  final SharedPreferences? _prefs;
  final Map<String, MatchRecord> _byId = {};

  /// Every record, newest first.
  List<MatchRecord> get all => _byId.values.toList()..sort((a, b) => b.playedAt.compareTo(a.playedAt));

  /// Waiting for the server, oldest first (the order they are sent in).
  List<MatchRecord> get pending => [
    for (final r in _byId.values)
      if (r.syncStatus == SyncStatus.pending) r,
  ]..sort((a, b) => a.playedAt.compareTo(b.playedAt));

  int get pendingCount => _byId.values.where((r) => r.syncStatus == SyncStatus.pending).length;
  int get failedCount => _byId.values.where((r) => r.syncStatus == SyncStatus.failed).length;

  /// Confirmed matches whose rating the server is still waiting on the other player for.
  List<MatchRecord> get awaitingOpponent => [
    for (final r in _byId.values)
      if (r.syncStatus == SyncStatus.synced && r.awaitingOpponent) r,
  ];

  int get length => _byId.length;
  MatchRecord? operator [](String matchId) => _byId[matchId];

  /// Saves a finished match. A match_id already here is left as it is (a result can be reported
  /// twice, it is still one match). Completes once the record is in storage.
  Future<bool> add(MatchRecord r) async {
    if (_byId.containsKey(r.matchId)) return false;
    _byId[r.matchId] = r;
    notifyListeners();
    await _write();
    return true;
  }

  /// Saves changes made to a record that is already here.
  Future<void> update(MatchRecord r) async {
    _byId[r.matchId] = r;
    notifyListeners();
    await _write();
  }

  void _read() {
    final raw = _prefs?.getString(_key);
    if (raw == null) return;
    try {
      for (final item in jsonDecode(raw) as List) {
        final r = MatchRecord.fromJson(item);
        if (r != null) _byId[r.matchId] = r;
      }
    } catch (_) {
      // A damaged save loses the list it was in, never the app.
    }
  }

  Future<void> _write() async {
    final p = _prefs;
    if (p == null) return;
    _trim();
    try {
      await p.setString(_key, jsonEncode([for (final r in _byId.values) r.toJson()]));
    } catch (_) {}
  }

  /// Only matches the server confirmed are ever dropped, oldest first, past [keepSynced].
  void _trim() {
    final synced = [
      for (final r in _byId.values)
        if (r.syncStatus == SyncStatus.synced && !r.awaitingOpponent) r,
    ]..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    for (final r in synced.skip(keepSynced)) {
      _byId.remove(r.matchId);
    }
  }
}
