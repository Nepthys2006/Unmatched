/// App-wide services (settings, audio, game data) handed down the tree.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../engine/defs.dart';
import 'audio.dart';
import 'settings.dart';

class Services {
  Services({required this.settings, required this.audio, this.preloadImages = true});

  final Settings settings;
  final Audio audio;

  /// Off in widget tests, where image decoding never finishes inside fake time.
  final bool preloadImages;
  GameData? _data;

  GameData get data => _data ?? (throw StateError('Game data not loaded yet'));
  bool get loaded => _data != null;

  /// Loads heroes.json and maps.json. Decoded here rather than with loadString, which hands big
  /// files to an isolate.
  Future<GameData> loadData([AssetBundle? bundle]) async {
    if (_data != null) return _data!;
    final b = bundle ?? rootBundle;
    Future<Object?> json(String path) async {
      final bytes = await b.load(path);
      return jsonDecode(utf8.decode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)));
    }

    final heroes = await json('assets/data/heroes.json') as List;
    final maps = await json('assets/data/maps.json') as Map<String, dynamic>;
    return _data = GameData.fromJson(heroes, maps);
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
