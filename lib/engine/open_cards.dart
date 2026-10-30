/// Cards a hero keeps on the table outside the hand: Pandora's MISERIES, Titania's GLAMOURS, the
/// Wayward Sisters' cauldron, Shakespeare's line... They are open information (everyone sees what
/// is face up and how many are face down), so the UI draws them for every player.
library;

import 'state.dart';

/// One card of an [OpenZone]. Cards that exist as printed cards carry their [image]; the others
/// (MISERIES, GLAMOURS, gadgets) have no scan, so the UI draws a face from [title] and [text].
class OpenCard {
  const OpenCard({required this.title, this.text = '', this.feathers, this.image, this.tag});

  factory OpenCard.of(Card c, {String? tag}) => OpenCard(title: c.title, image: c.def.image, tag: tag);

  final String title;
  final String text;

  /// MISERIES: feathers on the card (0 shows none).
  final int? feathers;

  /// Asset path of the printed card, when there is one.
  final String? image;

  /// A short corner label ("ingredient: snake", "3 syllables").
  final String? tag;
}

/// A place on the table where a hero keeps cards: [cards] lie face up, [hidden] more lie face down.
class OpenZone {
  const OpenZone({
    required this.id,
    required this.label,
    this.short,
    this.kind = OpenZoneKind.pile,
    this.cards = const [],
    this.hidden = 0,
    this.hiddenLabel = 'face down',
    this.peek,
    this.peekLabel = 'Next card',
    this.note = '',
    this.alwaysShow = true,
  });

  final String id;

  /// "MISERIES", "GLAMOUR", "CAULDRON"...
  final String label;

  /// The name on a tight chip ("MISERIES" for Pandora's Box); [label] when null.
  final String? short;
  final OpenZoneKind kind;

  /// Face-up cards, in order.
  final List<OpenCard> cards;

  /// Cards of this zone that lie face down (the rest of Pandora's Box, the glamour deck).
  final int hidden;
  final String hiddenLabel;

  /// A face-down card only the owner may look at (Pandora's Hope). The UI shows it to the owner
  /// alone.
  final OpenCard? peek;
  final String peekLabel;

  /// One line under the cards: the feathers so far, the syllables of the line.
  final String note;

  /// Show the zone even while it is empty (Pandora's Box has cards face down from the start).
  final bool alwaysShow;

  String get chip => short ?? label;
  int get total => cards.length + hidden;
  int get feathers => cards.fold(0, (n, c) => n + (c.feathers ?? 0));
}

enum OpenZoneKind {
  /// Cards lying in a pile or a row (the cauldron, the line, the suit, MISERIES).
  pile,

  /// One card that is "the" active one, with a deck behind it (Titania's glamour, Jill's gadget).
  active,
}

/// How a hero's special cards read in text: shared by status lines, logs and tests.
String describe(OpenZone z) {
  final up = z.cards.isEmpty ? 'none face up' : z.cards.map((c) => c.title).join(', ');
  return '${z.label}: $up${z.hidden > 0 ? ' (+${z.hidden} ${z.hiddenLabel})' : ''}';
}
