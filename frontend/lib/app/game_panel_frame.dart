import 'package:flutter/material.dart';

/// A book/paper surface floats in the hall, never a separate app shell.
class GamePanelFrame extends StatelessWidget {
  const GamePanelFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset('assets/images/campus_hall_v1.png', fit: BoxFit.cover),
      const ColoredBox(color: Color(0xA6201711)),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF4A321E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFB58A48), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
