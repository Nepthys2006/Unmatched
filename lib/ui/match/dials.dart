/// The fan of card backs that shows how many cards an opponent holds. (Health is on the player
/// plates' heart cells and the fighters' tags: plate_parts.dart.)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../shapes.dart';
import '../theme.dart';
import '../widgets.dart';

/// An opponent's hand as fanned card backs with the count, so you can see how many they hold.
class HandBacks extends StatelessWidget {
  const HandBacks({super.key, required this.count, required this.back, this.height = 30});
  final int count;
  final String back;
  final double height;

  @override
  Widget build(BuildContext context) {
    final w = height * cardAspect;
    final shown = math.min(count, 8);
    final spacing = w * 0.42;
    final width = shown == 0 ? w : w + spacing * (shown - 1);
    return Tooltip(
      message: '$count card${count == 1 ? '' : 's'} in hand',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (shown == 0)
                  Container(
                    width: w,
                    height: height,
                    decoration: ShapeDecoration(shape: ChamferBorder(cut: 3, side: BorderSide(color: Palette.bone.withValues(alpha: 0.25)))),
                  ),
                for (var i = 0; i < shown; i++)
                  Positioned(
                    left: spacing * i,
                    top: 0,
                    child: Transform.rotate(
                      angle: shown == 1 ? 0 : (i / (shown - 1) - 0.5) * 0.35,
                      alignment: Alignment.bottomCenter,
                      child: CardImage(back, width: w),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text('$count', style: titleStyle(height * 0.55, spacing: 0)),
        ],
      ),
    );
  }
}
