import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/module_body.dart';
import '../models/task.dart';
import '../services/focus_timer.dart';

class FocusTimerPage extends StatefulWidget {
  const FocusTimerPage({super.key, required this.timer, this.task});

  final FocusTimer timer;
  final Task? task;

  @override
  State<FocusTimerPage> createState() => _FocusTimerPageState();
}

class _FocusTimerPageState extends State<FocusTimerPage> {
  FocusTimer get _timer => widget.timer;
  Timer? _ticker;
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    if (task != null && (!_timer.started || _timer.finished)) {
      _timer.configure(
        Duration(minutes: task.estimatedMinutes.clamp(1, 180)),
        label: task.title,
      );
    }
    _announced = _timer.finished;
    if (_timer.running) _startTicks();
  }

  void _startTicks() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_timer.finished && !_announced) {
        _announced = true;
        _timer.pause();
        _ticker?.cancel();
        if (ModalRoute.of(context)?.isCurrent == true) {
          SystemSound.play(SystemSoundType.alert);
        }
      }
      setState(() {});
    });
  }

  void _toggle() {
    if (_timer.running) {
      _timer.pause();
      _ticker?.cancel();
    } else {
      _announced = false;
      _timer.start();
      _startTicks();
    }
    setState(() {});
  }

  void _configure(int minutes) {
    _ticker?.cancel();
    setState(
      () => _timer.configure(Duration(minutes: minutes), label: _timer.label),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_timer.remaining.inMilliseconds / 1000).ceil();
    final display =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final status = _timer.finished
        ? '本轮完成'
        : _timer.running
        ? '专注中'
        : _timer.started
        ? '已暂停'
        : '准备开始';
    return Scaffold(
      appBar: AppBar(title: const Text('专注计时')),
      body: ModuleBody(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_timer.label case final label?)
              Text(label, style: Theme.of(context).textTheme.titleLarge),
            Text(status),
            Semantics(
              label: '剩余 ${seconds ~/ 60} 分 ${seconds % 60} 秒',
              excludeSemantics: true,
              child: Text(
                display,
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            LinearProgressIndicator(
              value:
                  1 -
                  _timer.remaining.inMilliseconds /
                      _timer.duration.inMilliseconds,
              semanticsLabel: '本轮专注进度',
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              children: [
                for (final minutes in [5, 15, 25, 45, 60])
                  ChoiceChip(
                    label: Text('$minutes 分钟'),
                    selected: _timer.duration.inMinutes == minutes,
                    onSelected: _timer.started && !_timer.finished
                        ? null
                        : (_) => _configure(minutes),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _toggle,
                  icon: Icon(_timer.running ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    _timer.running
                        ? '暂停'
                        : _timer.finished
                        ? '再来一轮'
                        : _timer.started
                        ? '继续'
                        : '开始',
                  ),
                ),
                TextButton(
                  onPressed: !_timer.started
                      ? null
                      : () {
                          _ticker?.cancel();
                          setState(_timer.reset);
                        },
                  child: const Text('重置'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('返回其他页面时继续计时。本轮进度在本次应用运行期间保留。'),
          ],
        ),
      ),
    );
  }
}
