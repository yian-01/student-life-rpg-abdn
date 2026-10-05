import 'package:flutter/material.dart';

class FinancePage extends StatelessWidget {
  const FinancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [Text('模块待接入')],
        ),
      ),
    );
  }
}
