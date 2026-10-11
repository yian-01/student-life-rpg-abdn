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
        if (!width.isFinite || width <= 0) return const SizedBox.shrink();
        final padding = math.min(12.0, width / 8);
        return Semantics(
          label:
              '${data.displayName}，等级 ${data.level}，'
              '经验 ${data.exp}/${data.expToNextLevel}',
          child: ExcludeSemantics(
            child: SizedBox(
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(padding),
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
            ),
          ),
        );
      },
    );
  }
}
