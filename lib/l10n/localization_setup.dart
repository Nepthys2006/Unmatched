/// The app's localization delegates. Flutter's own Material / Widgets / Cupertino texts are not
/// translated into every language the app has (Bisaya, `ceb`, is missing from all three), and
/// asking for a language a delegate does not know makes the whole app throw "no MaterialLocalizations
/// found". So each built-in delegate is wrapped: for a language it does not support it loads
/// English instead.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Loads [inner] for the languages it knows and English for all the others.
class FallbackLocalizationsDelegate<T> extends LocalizationsDelegate<T> {
  const FallbackLocalizationsDelegate(this.inner);
  final LocalizationsDelegate<T> inner;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => inner.load(inner.isSupported(locale) ? locale : const Locale('en'));

  @override
  bool shouldReload(covariant LocalizationsDelegate<T> old) => false;
}

const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  FallbackLocalizationsDelegate<MaterialLocalizations>(GlobalMaterialLocalizations.delegate),
  FallbackLocalizationsDelegate<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
  FallbackLocalizationsDelegate<CupertinoLocalizations>(GlobalCupertinoLocalizations.delegate),
];

const List<Locale> appSupportedLocales = AppLocalizations.supportedLocales;

/// Picks the app's language from the device's list: the first language the app has (Tagalog `tl`
/// counts as Filipino), and English for everything else. Without this Flutter would fall back to the
/// FIRST supported locale, which alphabetically is Bisaya.
Locale resolveAppLocale(List<Locale>? device, Iterable<Locale> supported) {
  for (final d in device ?? const <Locale>[]) {
    final code = d.languageCode == 'tl' ? 'fil' : d.languageCode;
    for (final s in supported) {
      if (s.languageCode == code) return s;
    }
  }
  return const Locale('en');
}
