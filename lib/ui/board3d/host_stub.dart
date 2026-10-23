/// Platforms without a web view: the 3D board is unavailable and the match uses the 2D board.
library;

import 'package:flutter/widgets.dart';

import 'board3d.dart';

bool get supported => false;

Widget buildHost(Board3DController c) {
  c.fail('3D board not supported on this platform');
  return const SizedBox.expand();
}
