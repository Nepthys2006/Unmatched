/// Hero id → script. Every playable hero must be listed here.
library;

import '../hero_script.dart';
import 'amaze.dart';
import 'bol1.dart';
import 'bol2.dart';
import 'bol3.dart';
import 'cobble.dart';
import 'fables.dart';
import 'marvel_buffy.dart';
import 'slings.dart';
import 'tmnt.dart';
import 'witcher_rf.dart';
import 'witcher_ss.dart';

final Map<String, HeroScript Function()> heroScripts = {
  'king-arthur': KingArthur.new,
  'alice': Alice.new,
  'medusa': Medusa.new,
  'sinbad': Sinbad.new,
  'bigfoot': Bigfoot.new,
  'robin-hood': RobinHood.new,
  'achilles': Achilles.new,
  'yennenga': Yennenga.new,
  'sun-wukong': SunWukong.new,
  'sherlock-holmes': SherlockHolmes.new,
  'dracula': Dracula.new,
  'jekyll-hyde': JekyllHyde.new,
  'invisible-man': InvisibleMan.new,
  'little-red': LittleRed.new,
  'beowulf': Beowulf.new,
  'ancient-leshen': AncientLeshen.new,
  'geralt-of-rivia': Geralt.new,
  'ciri': Ciri.new,
  'doctor-strange': DoctorStrange.new,
  'black-widow': BlackWidow.new,
  'willow': Willow.new,
  'hamlet': Hamlet.new,
  'titania': Titania.new,
  'the-genie': Genie.new,
  'harry-houdini': Houdini.new,
  'annie-christmas': AnnieChristmas.new,
  'nikola-tesla': Tesla.new,
  'golden-bat': GoldenBat.new,
  'eredin': Eredin.new,
  'philippa': Philippa.new,
  'yennefer-triss': YenneferTriss.new,
  'moon-knight': MoonKnight.new,
  'leonardo': Leonardo.new,
  'donatello': Donatello.new,
  'michelangelo': Michelangelo.new,
  'shredder': Shredder.new,
  'krang': Krang.new,
  'loki': Loki.new,
  'blackbeard': Blackbeard.new,
};

/// Heroes whose ability and every card are scripted and tested.
bool isImplemented(String heroId) => heroScripts.containsKey(heroId);

HeroScript createHeroScript(String heroId) => (heroScripts[heroId] ?? Unscripted.new)();

/// Placeholder for heroes not scripted yet: plays by the core rules, card effects do nothing.
class Unscripted extends HeroScript {
  @override
  Map<String, CardScript> get cards => const {};
}
