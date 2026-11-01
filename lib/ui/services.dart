/// App-wide services (settings, audio, game data) handed down the tree.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../engine/defs.dart';
import '../engine/heroes/registry.dart';
import '../engine/ismcts/evaluator.dart';
import '../net/match_store.dart';
import '../net/match_sync.dart';
import '../net/profile_stats.dart';
import '../net/rules_version.dart';
import 'platform/fullscreen_controller.dart';
import 'platform/fullscreen_help_storage.dart';
import 'platform/platform_info_factory.dart';
import 'platform/platform_info_service.dart';
import 'audio.dart';
import 'settings.dart';

class Services {
  Services({
    required this.settings,
    required this.audio,
    this.preloadImages = true,
    MatchStore? matchStore,
    MatchBackend? matchBackend,
    PlatformInfoService? platformInfo,
    FullscreenHelpStorage? helpStorage,
    this.debugPanel = false,
  }) {
    fullscreen = FullscreenController(
      platform: platformInfo ?? createPlatformInfoService(),
      storage: helpStorage ?? const SharedPrefsFullscreenHelpStorage(),
    );
    unawaited(fullscreen.load());
    matches = matchStore ?? MatchStore.memory();
    sync = MatchSyncService(
      store: matches,
      backend: matchBackend ?? const NoBackend(),
      token: () => settings.accountToken,
      accountId: () => settings.accountId,
      onAccountId: (id) => settings.update((x) => x.accountId = id),
      onProfile: ProfileStats.instance.applyServerProfile,
    );
  }

  final Settings settings;
  final Audio audio;

  /// Show the hidden debug panel's launcher (debug builds and `?debug=1`; set by main()).
  final bool debugPanel;

  /// What the Full Screen button does on this device, and whether the Home Screen help may show.
  late final FullscreenController fullscreen;

  /// The debug panel's "Simulate portrait / Split View": the window size the app should pretend to
  /// have (null: the real one). Never set in a normal session.
  final ValueNotifier<Size?> simulatedWindow = ValueNotifier(null);

  /// Every finished match, saved on this device first.
  late final MatchStore matches;

  /// Sends the saved matches to the server whenever it can, and tells how that is going.
  late final MatchSyncService sync;

  /// Off in widget tests, where image decoding never finishes inside fake time.
  final bool preloadImages;
  GameData? _data;
  Evaluator? _umccc;

  /// The UMCCC Model's trained evaluator (the hand-tuned one if the file could not be loaded).
  Evaluator get umcccEvaluator => _umccc ?? HeuristicEvaluator();
  bool get umcccLoaded => _umccc != null;

  /// Loads assets/ai/umccc_model.json. A failure is logged and leaves the fallback in place.
  Future<void> loadUmcccModel([AssetBundle? bundle]) async {
    if (_umccc != null) return;
    try {
      final bytes = await (bundle ?? rootBundle).load('assets/ai/umccc_model.json');
      final text = utf8.decode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      _umccc = LearnedEvaluator.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('UMCCC Model could not be loaded: $e');
    }
  }

  GameData get data => _data ?? (throw StateError('Game data not loaded yet'));

  /// Fingerprint of the rules data (see rules_version.dart): multiplayer pairs devices that play the
  /// same rules, whatever platform or build they run.
  String dataVersion = '';
  bool get loaded => _data != null;

  /// Loads heroes.json and maps.json. Decoded here rather than with loadString, which hands big
  /// files to an isolate.
  Future<GameData> loadData([AssetBundle? bundle]) async {
    if (_data != null) return _data!;
    final b = bundle ?? rootBundle;
    Future<Object?> json(String path) async {
      final bytes = await b.load(path);
      final list = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
      return jsonDecode(utf8.decode(list));
    }

    final heroes = await json('assets/data/heroes.json') as List;
    final maps = await json('assets/data/maps.json') as Map<String, dynamic>;
    // heroes.json lists all 70 heroes; only those whose cards are scripted are playable.
    final data = GameData.fromJson(heroes, maps)..heroes.removeWhere((id, _) => !isImplemented(id));
    dataVersion = rulesFingerprint(heroes, maps, playable: data.heroes.keys);
    return _data = data;
  }
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({super.key, required this.services, required super.child});
  final Services services;

  static Services of(BuildContext context) => context.getInheritedWidgetOfExactType<ServicesScope>()!.services;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) => services != oldWidget.services;
}

extension ServicesContext on BuildContext {
  Services get services => ServicesScope.of(this);
}
