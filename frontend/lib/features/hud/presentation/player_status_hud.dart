import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/hud_view_data.dart';

class PlayerStatusHud extends StatelessWidget {
  const PlayerStatusHud({super.key, required this.data});

  final HudViewData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 280.0);
        if (!width.isFinite || width <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }
        // Below a glyph's width, wrapping alone paints outside the viewport.
        // Keep text at the user's chosen size and allow scrolling instead.
        final contentWidth = math.max(
          width,
          MediaQuery.textScalerOf(context).scale(24) + 24,
        );
        final content = SizedBox(
          width: contentWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.displayName, softWrap: true),
                  Text('Lv ${data.level}', softWrap: true),
                  Text(
                    'EXP ${data.exp}/${data.expToNextLevel}',
                    softWrap: true,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: data.ratio),
                ],
              ),
            ),
          ),
        );
        return Semantics(
          label:
              '${data.displayName}，等级 ${data.level}，'
              '经验 ${data.exp}/${data.expToNextLevel}',
          child: ExcludeSemantics(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                primary: false,
                child: contentWidth > width
                    ? SingleChildScrollView(
                        primary: false,
                        scrollDirection: Axis.horizontal,
                        child: content,
                      )
                    : content,
              ),
            ),
          ),
        );
      },
    );
  }
}
