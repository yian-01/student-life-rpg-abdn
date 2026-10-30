import 'package:flutter/material.dart';

class ModuleBody extends StatelessWidget {
  const ModuleBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1040),
      child: child,
    ),
  );
}
