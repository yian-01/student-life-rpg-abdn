import 'package:flutter/material.dart';

import 'app_routes.dart';

class UnknownRoutePage extends StatelessWidget {
  const UnknownRoutePage({super.key, required this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('未知路由：${routeName ?? "未指定"}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(AppRoutes.bedroom, (_) => false),
              child: const Text('回到卧室'),
            ),
          ],
        ),
      ),
    );
  }
}
