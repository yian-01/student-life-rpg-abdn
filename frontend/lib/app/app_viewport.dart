import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The Navigator, overlays, app bars and actions share one mobile viewport.
class AppViewport extends StatelessWidget {
  const AppViewport({super.key, required this.child});
  final Widget child;
  static const maxWidth = 430.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(maxWidth, constraints.maxWidth);
      return ColoredBox(
        color: const Color(0xFF171612),
        child: Center(
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(size: Size(width, constraints.maxHeight)),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
