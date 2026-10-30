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
        final width = math.min(constraints.maxWidth, 128.0);
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
              color: const Color(0xF0212828),
              border: Border.all(color: const Color(0xFFB99552)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Color(0xFFF6EBD3),
                fontSize: 11,
                height: 1.25,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.displayName,
                      softWrap: true,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Lv ${data.level}',
                          style: const TextStyle(
                            color: Color(0xFFE8BF70),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'EXP ${data.exp}/${data.expToNextLevel}',
                          style: const TextStyle(color: Color(0xFFC8D5CD)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: data.ratio,
                        minHeight: 4,
                        color: const Color(0xFFDBB464),
                        backgroundColor: const Color(0xFF404C45),
                      ),
                    ),
                  ],
                ),
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
