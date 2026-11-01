// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Cebuano (`ceb`).
class AppLocalizationsCeb extends AppLocalizations {
  AppLocalizationsCeb([String locale = 'ceb']) : super(locale);

  @override
  String get fsTitleIphone => 'Full screen sa iPhone';

  @override
  String get fsTitleIpad => 'Full screen sa iPad';

  @override
  String get fsBodyIphone =>
      'Dili mabutang sa Safari ang web page sa full screen sa iPhone. Idugang ang Unmatched sa imong Home Screen ug ablihi gikan didto: modagan kini nga walay mga bar sa Safari.';

  @override
  String get fsBodyIpad =>
      'Idugang ang Unmatched sa imong Home Screen ug ablihi gikan didto: modagan kini sa full screen nga walay mga bar sa Safari.';

  @override
  String get fsStepShareIphoneSafari => 'I-tap ang Share sa Safari';

  @override
  String get fsStepShareIpadSafari =>
      'I-tap ang Share sa taas nga bar sa Safari';

  @override
  String get fsStepShareOther =>
      'I-tap ang Share (o ang menu) sa imong browser';

  @override
  String get fsStepAdd => 'Pilia ang Add to Home Screen';

  @override
  String get fsStepOpen => 'Ablihi ang Unmatched gikan sa imong Home Screen';

  @override
  String get fsGotIt => 'Okay';

  @override
  String get fsDialogLabel => 'Idugang ang Unmatched sa imong Home Screen';

  @override
  String fsStepNumber(int number) {
    return 'Lakang $number';
  }

  @override
  String get fsButtonEnter => 'Full screen';

  @override
  String get fsButtonExit => 'Gawas sa full screen';

  @override
  String get fsInstallApp => 'Mas maayong full screen: i-install ang app';

  @override
  String get fsInstallAppHint =>
      'Idugang ang Unmatched sa imong Home Screen aron makadula nga walay mga bar sa Safari.';

  @override
  String get rotateTitle => 'Ilisdi ang imong telepono';

  @override
  String get rotateBody => 'Gidula ang Unmatched nga pahigda.';

  @override
  String get largerTitle => 'Padak-a kini nga window';

  @override
  String get largerBody =>
      'Mas kinahanglan ug luna ang Unmatched. Gamaya ang window, o ablihi kini sa full screen.';
}
