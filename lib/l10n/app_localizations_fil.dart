// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Filipino Pilipino (`fil`).
class AppLocalizationsFil extends AppLocalizations {
  AppLocalizationsFil([String locale = 'fil']) : super(locale);

  @override
  String get fsTitleIphone => 'Full screen sa iPhone';

  @override
  String get fsTitleIpad => 'Full screen sa iPad';

  @override
  String get fsBodyIphone =>
      'Hindi kayang i-full screen ng Safari ang web page sa iPhone. Idagdag ang Unmatched sa iyong Home Screen at buksan doon: tatakbo ito nang walang mga bar ng Safari.';

  @override
  String get fsBodyIpad =>
      'Idagdag ang Unmatched sa iyong Home Screen at buksan doon: tatakbo ito nang full screen at walang mga bar ng Safari.';

  @override
  String get fsStepShareIphoneSafari => 'I-tap ang Share sa Safari';

  @override
  String get fsStepShareIpadSafari =>
      'I-tap ang Share sa itaas na bar ng Safari';

  @override
  String get fsStepShareOther =>
      'I-tap ang Share (o ang menu) sa iyong browser';

  @override
  String get fsStepAdd => 'Piliin ang Add to Home Screen';

  @override
  String get fsStepOpen => 'Buksan ang Unmatched mula sa iyong Home Screen';

  @override
  String get fsGotIt => 'Sige';

  @override
  String get fsDialogLabel => 'Idagdag ang Unmatched sa iyong Home Screen';

  @override
  String fsStepNumber(int number) {
    return 'Hakbang $number';
  }

  @override
  String get fsButtonEnter => 'Full screen';

  @override
  String get fsButtonExit => 'Lumabas sa full screen';

  @override
  String get fsInstallApp => 'Mas magandang full screen: i-install ang app';

  @override
  String get fsInstallAppHint =>
      'Idagdag ang Unmatched sa iyong Home Screen para maglaro nang walang mga bar ng Safari.';

  @override
  String get rotateTitle => 'I-ikot ang iyong telepono';

  @override
  String get rotateBody => 'Nilalaro ang Unmatched nang pahalang.';

  @override
  String get largerTitle => 'Palakihin ang window na ito';

  @override
  String get largerBody =>
      'Kailangan ng Unmatched ng mas maluwag na espasyo. Iladlad ang window, o buksan ito nang full screen.';
}
