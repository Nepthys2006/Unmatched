/// Player accounts (username + password) on the game's Supabase backend, the same account on
/// every device. The device keeps a session token, not the password.
library;

import 'dart:async';

import 'package:supabase/supabase.dart';

import 'online.dart' show isOnlineConfigured, newSupabaseClient;

/// Usernames: 3-16 letters, numbers or _, unique ignoring capitals (checked on the server too).
final usernamePattern = RegExp(r'^[A-Za-z0-9_]{3,16}$');

String? usernameError(String raw) {
  final u = raw.trim();
  if (u.isEmpty) return 'Enter a username.';
  if (!usernamePattern.hasMatch(u)) return '3 to 16 letters, numbers or _ (no spaces).';
  return null;
}

String? passwordError(String password, {String? username}) {
  if (password.length < 6) return 'At least 6 characters.';
  if (password.length > 72) return 'At most 72 characters.';
  if (username != null && password.toLowerCase() == username.trim().toLowerCase()) {
    return "Can't be the same as the username.";
  }
  return null;
}

typedef SignedIn = ({String username, String token});

class AccountService {
  AccountService({SupabaseClient? client}) : _given = client;
  final SupabaseClient? _given;
  SupabaseClient? _made;
  SupabaseClient get _c => _given ?? (_made ??= newSupabaseClient());

  Future<Object?> _call(String fn, Map<String, Object?> params) async {
    if (_given == null && !isOnlineConfigured) {
      throw StateError("Online accounts are not configured.");
    }
    try {
      return await _c.rpc(fn, params: params).timeout(const Duration(seconds: 12));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.message.contains('Could not find the function')) {
        throw StateError("Accounts aren't set up on the server yet.");
      }
      throw StateError(e.message);
    } on TimeoutException {
      throw StateError("The server didn't answer. Check your internet connection.");
    } catch (e) {
      if (e is StateError) rethrow;
      throw StateError("Can't reach the server. Check your internet connection.");
    }
  }

  SignedIn _row(Object? r) {
    final row = (r is List ? r.first : r) as Map;
    return (username: row['username'] as String, token: row['token'] as String);
  }

  Future<SignedIn> register(String username, String password) async =>
      _row(await _call('register_account', {'p_username': username.trim(), 'p_password': password}));

  Future<SignedIn> signIn(String username, String password) async =>
      _row(await _call('sign_in', {'p_username': username.trim(), 'p_password': password}));

  /// The username a saved token belongs to, or null when it was signed out. Throws when the
  /// server can't be reached (the caller may then keep the saved name and play offline).
  Future<String?> check(String token) async => await _call('check_session', {'p_token': token}) as String?;

  Future<void> signOut(String token) async {
    try {
      await _call('sign_out', {'p_token': token});
    } catch (_) {}
  }
}
