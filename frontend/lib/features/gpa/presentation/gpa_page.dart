import 'package:flutter/material.dart';

class GpaPage extends StatelessWidget {
  const GpaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GPA')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [Text('模块待接入')],
        ),
      ),
    );
  }
}
