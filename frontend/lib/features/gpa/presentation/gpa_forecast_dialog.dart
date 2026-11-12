import 'package:flutter/material.dart';

import '../models/gpa_result.dart';
import '../services/gpa_forecast.dart';

class GpaForecastDialog extends StatefulWidget {
  const GpaForecastDialog({
    super.key,
    required this.current,
    required this.scaleMax,
    required this.suggestedCredits,
    required this.scope,
  });

  final GpaResult current;
  final double scaleMax;
  final double suggestedCredits;
  final String scope;

  @override
  State<GpaForecastDialog> createState() => _GpaForecastDialogState();
}

class _GpaForecastDialogState extends State<GpaForecastDialog> {
  late final _target = TextEditingController(
    text: (widget.scaleMax * 0.8).toStringAsFixed(2),
  );
  late final _credits = TextEditingController(
    text: widget.suggestedCredits > 0 ? widget.suggestedCredits.toString() : '',
  );
  GpaForecast? _forecast;
  String? _error;

  @override
  void dispose() {
    _target.dispose();
    _credits.dispose();
    super.dispose();
  }

  void _calculate() {
    try {
      final forecast = forecastGpa(
        widget.current,
        target: double.tryParse(_target.text.trim()) ?? double.nan,
        futureCredits: double.tryParse(_credits.text.trim()) ?? double.nan,
        scaleMax: widget.scaleMax,
      );
      setState(() {
        _forecast = forecast;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _forecast = null;
        _error = error.message;
      });
    }
  }

  void _clear(String _) {
    if (_forecast == null && _error == null) return;
    setState(() {
      _forecast = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('目标 GPA 试算'),
    scrollable: true,
    content: SizedBox(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${widget.scope} · 已评分 ${widget.current.gradedCredits} 学分'),
          TextField(
            controller: _target,
            onChanged: _clear,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '目标 GPA（满分 ${widget.scaleMax.toStringAsFixed(1)}）',
            ),
          ),
          TextField(
            controller: _credits,
            onChanged: _clear,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '接下来计入的学分'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_forecast case final forecast?) ...[
            const SizedBox(height: 12),
            Text(
              forecast.reachable
                  ? '这些学分平均需要 ${forecast.requiredAverage.toStringAsFixed(2)} 绩点。'
                  : '按这些学分计算，所需平均绩点超过满分。',
            ),
            Text('全部拿满绩点时可达到 ${forecast.maximumReachable.toStringAsFixed(2)}。'),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(onPressed: _calculate, child: const Text('计算')),
    ],
  );
}
