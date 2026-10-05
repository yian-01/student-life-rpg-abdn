import 'package:flutter/material.dart';

import '../../../app/app_routes.dart';

class BedroomPage extends StatelessWidget {
  const BedroomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Life RPG')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            FilledButton(
              onPressed: () => Navigator.of(context).pushNamed(AppRoutes.menu),
              child: const Text('进入菜单'),
            ),
          ],
        ),
      ),
    );
  }
}
