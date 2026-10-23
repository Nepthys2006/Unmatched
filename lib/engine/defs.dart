/// Static game data: heroes, fighters, cards and battlefields, parsed from assets/data/*.json.
library;

enum CardType { attack, defense, versatile, scheme }

enum AttackType { melee, ranged }

CardType _cardType(String s) => CardType.values.byName(s.toLowerCase());

final Map<String, String> _norm = {};

/// Upper-cased card title with symbols removed and quotes straightened ("THE WOLF'S SKIN").
const _fold = {'Ö': 'O', 'ö': 'o', 'Ä': 'A', 'ä': 'a', 'Ü': 'U', 'ü': 'u', 'Æ': 'AE', 'æ': 'ae', 'Ð': 'D', 'ð': 'd', 'É': 'E', 'é': 'e'};

String normTitle(String title) => _norm[title] ??= title
    .split('')
    .map((ch) => _fold[ch] ?? ch)
    .join()
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp(r'[^ -~]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toUpperCase();

class CardDef {
  CardDef({
    required this.heroId,
    required this.index,
    required this.title,
    required this.type,
    required this.value,
    required this.boost,
    required this.copies,
    required this.fighters,
    required this.usedBy,
    required this.text,
    this.dieBoost = false,
  });

  factory CardDef.fromJson(String heroId, Map<String, dynamic> j) => CardDef(
        heroId: heroId,
        index: j['index'] as int,
        title: j['title'] as String,
        type: _cardType(j['type'] as String),
        value: j['value'] as int?,
        boost: j['boost'] as int?,
        copies: j['copies'] as int,
        fighters: [for (final f in j['fighters'] as List) f as String],
        usedBy: j['usedBy'] as String,
        text: {for (final e in (j['text'] as Map).entries) e.key as String: e.value as String},
        dieBoost: j['dieBoost'] as bool? ?? false,
      );

  final String heroId;
  final int index;
  final String title;
  final CardType type;
  final int? value;
  final int? boost;
  final int copies;

  /// Fighter ids that may play this card; empty means any fighter.
  final List<String> fighters;
  final String usedBy;

  /// Printed text by timing: effect, immediately, during, after, ongoing, boosted.
  final Map<String, String> text;

  /// The BOOST value is a roll of Krang's Die of Ultimate Destruction.
  final bool dieBoost;
  bool get canBoost => boost != null || dieBoost;

  String get key => '$heroId/$index';
  String get image => 'assets/cards/$heroId/${index.toString().padLeft(2, '0')}.webp';
  bool get isAny => fighters.isEmpty;
  bool get canAttack => type == CardType.attack || type == CardType.versatile;
  bool get canDefend => type == CardType.defense || type == CardType.versatile;
  bool get isScheme => type == CardType.scheme;

  /// Upper-cased title without the symbols some decks print after the name.
  String get upperTitle => normTitle(title);
  bool titleHas(String word) => upperTitle.contains(word.toUpperCase());

  @override
  String toString() => title;
}

class FighterDef {
  FighterDef({
    required this.id,
    required this.name,
    required this.isHero,
    required this.attack,
    required this.hp,
    required this.count,
  });

  factory FighterDef.fromJson(Map<String, dynamic> j) => FighterDef(
        id: j['id'] as String,
        name: j['name'] as String,
        isHero: j['hero'] as bool,
        attack: (j['attack'] as String).startsWith('r') ? AttackType.ranged : AttackType.melee,
        hp: j['hp'] as int,
        count: j['count'] as int,
      );

  final String id;
  final String name;
  final bool isHero;
  final AttackType attack;
  final int hp;
  final int count;
}

class HeroDef {
  HeroDef({
    required this.id,
    required this.name,
    required this.set,
    required this.color,
    required this.move,
    required this.ability,
    required this.description,
    required this.fighters,
    required this.cards,
  });

  factory HeroDef.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    return HeroDef(
      id: id,
      name: j['name'] as String,
      set: j['set'] as String,
      color: j['color'] as String,
      move: j['move'] as int,
      ability: j['ability'] as String,
      description: j['description'] as String? ?? '',
      fighters: [for (final f in j['fighters'] as List) FighterDef.fromJson(f as Map<String, dynamic>)],
      cards: [for (final c in j['cards'] as List) CardDef.fromJson(id, c as Map<String, dynamic>)],
    );
  }

  final String id;
  final String name;
  final String set;
  final String color;
  final int move;
  final String ability;
  final String description;
  final List<FighterDef> fighters;
  final List<CardDef> cards;

  FighterDef get hero => fighters.first;
  Iterable<FighterDef> get sidekicks => fighters.skip(1);
  int get deckSize => cards.fold(0, (n, c) => n + c.copies);
  String get avatar => 'assets/heroes/$id/avatar.webp';
  String get mini => 'assets/heroes/$id/mini.webp';
  String get back => 'assets/heroes/$id/back.webp';
  String get identity => 'assets/heroes/$id/identity.webp';
  String token(String fighterId) => 'assets/heroes/$id/$fighterId.webp';
  CardDef card(String title) =>
      cards.firstWhere((c) => c.upperTitle == normTitle(title), orElse: () => throw StateError('$id has no card "$title"'));
}

class ZoneDef {
  ZoneDef(this.key, this.name, this.color);
  final String key;
  final String name;
  final String color;
}

class SpaceDef {
  SpaceDef(this.id, this.x, this.y, this.zones, this.start);
  final int id;
  final double x;
  final double y;
  final Set<String> zones;
  final int? start;
}

class MapDef {
  MapDef({
    required this.id,
    required this.name,
    required this.mode,
    required this.theme,
    required this.blurb,
    required this.zones,
    required this.spaces,
    required this.links,
    this.river = false,
  });

  factory MapDef.fromJson(Map<String, dynamic> j) => MapDef(
        id: j['id'] as String,
        name: j['name'] as String,
        mode: j['mode'] as String,
        theme: j['theme'] as String,
        blurb: j['blurb'] as String,
        river: j['river'] as bool? ?? false,
        zones: {
          for (final e in (j['zones'] as Map).entries)
            e.key as String: ZoneDef(e.key as String, (e.value as Map)['name'] as String, (e.value as Map)['color'] as String)
        },
        spaces: [
          for (final s in j['spaces'] as List)
            SpaceDef(
              (s as Map)['id'] as int,
              (s['x'] as num).toDouble(),
              (s['y'] as num).toDouble(),
              {for (final z in s['zones'] as List) z as String},
              s['start'] as int?,
            )
        ],
        links: [for (final l in j['links'] as List) ((l as List)[0] as int, l[1] as int)],
      );

  final String id;
  final String name;
  final String mode;
  final String theme;
  final String blurb;
  final Map<String, ZoneDef> zones;
  final List<SpaceDef> spaces;
  final List<(int, int)> links;
  final bool river;
}

/// All loaded data. The app fills it from assets; tests read the JSON files directly.
class GameData {
  GameData(this.heroes, this.maps);

  factory GameData.fromJson(List<dynamic> heroes, Map<String, dynamic> maps) => GameData(
        {for (final h in heroes) (h as Map<String, dynamic>)['id'] as String: HeroDef.fromJson(h)},
        {for (final e in maps.entries) e.key: MapDef.fromJson(e.value as Map<String, dynamic>)},
      );

  final Map<String, HeroDef> heroes;
  final Map<String, MapDef> maps;

  HeroDef hero(String id) => heroes[id] ?? (throw ArgumentError('Unknown hero $id'));
  List<MapDef> mapsFor(String mode) => maps.values.where((m) => m.mode == mode).toList();
}
