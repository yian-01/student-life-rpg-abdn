/// Wheel events do not expose a portable finger-lift event. Consume the whole
/// inertial stream; only a quiet interval permits another page change.
class PageGesture {
  PageGesture({
    this.threshold = 96,
    this.quiet = const Duration(milliseconds: 320),
  });
  final double threshold;
  final Duration quiet;
  Duration? _last;
  double _travel = 0;
  bool _consumed = false;

  int? add({
    required double x,
    required double y,
    required Duration time,
    bool blocked = false,
  }) {
    if (_last == null || time - _last! >= quiet) {
      _travel = 0;
      _consumed = false;
    }
    _last = time;
    if (blocked) {
      _travel = 0;
      _consumed = true;
      return null;
    }
    if (_consumed) return null;
    if (x.abs() <= y.abs() * 1.25 || x.abs() <= .01) {
      if (y.abs() > x.abs()) _travel = 0;
      return null;
    }
    _travel += x.clamp(-120, 120);
    if (_travel.abs() < threshold) return null;
    _consumed = true;
    return _travel > 0 ? 1 : -1;
  }
}
