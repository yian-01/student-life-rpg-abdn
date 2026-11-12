/// Process-scoped countdown. A monotonic stopwatch keeps the elapsed time
/// correct when widget ticks are delayed or the timer screen is closed.
class FocusTimer {
  FocusTimer({Stopwatch? stopwatch}) : _stopwatch = stopwatch ?? Stopwatch();

  final Stopwatch _stopwatch;
  Duration _duration = const Duration(minutes: 25);
  bool _started = false;
  String? _label;

  Duration get duration => _duration;
  String? get label => _label;
  bool get started => _started;
  bool get finished => _started && remaining == Duration.zero;
  bool get running => _stopwatch.isRunning && !finished;

  Duration get remaining {
    final value = _duration - _stopwatch.elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  void configure(Duration duration, {String? label}) {
    if (duration <= Duration.zero)
      throw ArgumentError.value(duration, 'duration');
    reset();
    _duration = duration;
    _label = label;
  }

  void start() {
    if (finished) reset();
    _started = true;
    _stopwatch.start();
  }

  void pause() => _stopwatch.stop();

  void reset() {
    _stopwatch.stop();
    _stopwatch.reset();
    _started = false;
  }
}
