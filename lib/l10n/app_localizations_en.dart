// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get fsTitleIphone => 'Full screen on iPhone';

  @override
  String get fsTitleIpad => 'Full screen on iPad';

  @override
  String get fsBodyIphone =>
      'Safari can\'t show a web page full screen on iPhone. Add Unmatched to your Home Screen and open it from there: it runs without Safari\'s bars.';

  @override
  String get fsBodyIpad =>
      'Add Unmatched to your Home Screen and open it from there: it runs full screen without Safari\'s bars.';

  @override
  String get fsStepShareIphoneSafari => 'Tap Share in Safari';

  @override
  String get fsStepShareIpadSafari => 'Tap Share in the top bar of Safari';

  @override
  String get fsStepShareOther => 'Tap Share (or the menu) in your browser';

  @override
  String get fsStepAdd => 'Choose Add to Home Screen';

  @override
  String get fsStepOpen => 'Open Unmatched from your Home Screen';

  @override
  String get fsGotIt => 'Got it';

  @override
  String get fsDialogLabel => 'Add Unmatched to your Home Screen';

  @override
  String fsStepNumber(int number) {
    return 'Step $number';
  }

  @override
  String get fsButtonEnter => 'Full screen';

  @override
  String get fsButtonExit => 'Exit full screen';

  @override
  String get fsInstallApp => 'Better full screen: install the app';

  @override
  String get fsInstallAppHint =>
      'Add Unmatched to your Home Screen to play without Safari\'s bars.';

  @override
  String get rotateTitle => 'Turn your phone';

  @override
  String get rotateBody => 'Unmatched is played in landscape.';

  @override
  String get largerTitle => 'Make this window larger';

  @override
  String get largerBody =>
      'Unmatched needs a bit more room. Drag the window wider, or open it full screen.';
}
