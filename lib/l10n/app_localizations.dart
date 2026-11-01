import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ceb.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fil.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ceb'),
    Locale('en'),
    Locale('fil'),
  ];

  /// Title of the help dialog on an iPhone (shown in capitals).
  ///
  /// In en, this message translates to:
  /// **'Full screen on iPhone'**
  String get fsTitleIphone;

  /// Title of the help dialog on an iPad (shown in capitals).
  ///
  /// In en, this message translates to:
  /// **'Full screen on iPad'**
  String get fsTitleIpad;

  /// No description provided for @fsBodyIphone.
  ///
  /// In en, this message translates to:
  /// **'Safari can\'t show a web page full screen on iPhone. Add Unmatched to your Home Screen and open it from there: it runs without Safari\'s bars.'**
  String get fsBodyIphone;

  /// No description provided for @fsBodyIpad.
  ///
  /// In en, this message translates to:
  /// **'Add Unmatched to your Home Screen and open it from there: it runs full screen without Safari\'s bars.'**
  String get fsBodyIpad;

  /// Step 1 on iPhone Safari: the Share button is in the bottom bar.
  ///
  /// In en, this message translates to:
  /// **'Tap Share in Safari'**
  String get fsStepShareIphoneSafari;

  /// Step 1 on iPad Safari: the Share button is at the top right.
  ///
  /// In en, this message translates to:
  /// **'Tap Share in the top bar of Safari'**
  String get fsStepShareIpadSafari;

  /// Step 1 in another iOS browser (Chrome, Firefox, Edge...).
  ///
  /// In en, this message translates to:
  /// **'Tap Share (or the menu) in your browser'**
  String get fsStepShareOther;

  /// No description provided for @fsStepAdd.
  ///
  /// In en, this message translates to:
  /// **'Choose Add to Home Screen'**
  String get fsStepAdd;

  /// No description provided for @fsStepOpen.
  ///
  /// In en, this message translates to:
  /// **'Open Unmatched from your Home Screen'**
  String get fsStepOpen;

  /// No description provided for @fsGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get fsGotIt;

  /// The dialog's accessible name (read by screen readers).
  ///
  /// In en, this message translates to:
  /// **'Add Unmatched to your Home Screen'**
  String get fsDialogLabel;

  /// No description provided for @fsStepNumber.
  ///
  /// In en, this message translates to:
  /// **'Step {number}'**
  String fsStepNumber(int number);

  /// No description provided for @fsButtonEnter.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get fsButtonEnter;

  /// No description provided for @fsButtonExit.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen'**
  String get fsButtonExit;

  /// No description provided for @fsInstallApp.
  ///
  /// In en, this message translates to:
  /// **'Better full screen: install the app'**
  String get fsInstallApp;

  /// No description provided for @fsInstallAppHint.
  ///
  /// In en, this message translates to:
  /// **'Add Unmatched to your Home Screen to play without Safari\'s bars.'**
  String get fsInstallAppHint;

  /// No description provided for @rotateTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn your phone'**
  String get rotateTitle;

  /// No description provided for @rotateBody.
  ///
  /// In en, this message translates to:
  /// **'Unmatched is played in landscape.'**
  String get rotateBody;

  /// No description provided for @largerTitle.
  ///
  /// In en, this message translates to:
  /// **'Make this window larger'**
  String get largerTitle;

  /// No description provided for @largerBody.
  ///
  /// In en, this message translates to:
  /// **'Unmatched needs a bit more room. Drag the window wider, or open it full screen.'**
  String get largerBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ceb', 'en', 'fil'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ceb':
      return AppLocalizationsCeb();
    case 'en':
      return AppLocalizationsEn();
    case 'fil':
      return AppLocalizationsFil();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
