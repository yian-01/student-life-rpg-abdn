/// 节次时刻表：把教务系统的"第 N 节"翻译成当天分钟数。
///
/// 每节的开始/结束时刻因学校而异，因此这里做成可替换的表，
/// 不在解析器里硬编码。默认值取自华南师范大学南海校区的作息安排
/// （每节 40 分钟，课间 10 分钟，第 2、3 节之间 20 分钟），
/// 导入预览页允许用户修正。
class PeriodTimeTable {
  const PeriodTimeTable(this._periods);

  /// 节次 → (开始分钟, 结束分钟)。
  final Map<int, (int, int)> _periods;

  Map<int, (int, int)> get periods => Map.unmodifiable(_periods);

  int get lastPeriod => _periods.keys.reduce((a, b) => a > b ? a : b);

  /// 第 [period] 节的时间范围；未定义的节次返回 null。
  (int, int)? operator [](int period) => _periods[period];

  /// 从第 [from] 节开始到第 [to] 节结束的时间范围。
  ///
  /// 任一端缺失、或起点晚于终点时返回 null，由调用方给出可读错误，
  /// 不猜测、不截断。
  (int start, int end)? rangeFor(int from, int to) {
    if (from > to) return null;
    final start = _periods[from];
    final end = _periods[to];
    if (start == null || end == null) return null;
    if (start.$1 >= end.$2) return null;
    return (start.$1, end.$2);
  }

  /// 华南师范大学南海校区默认作息（11 节）。
  static const scnuNanhai = PeriodTimeTable({
    1: (8 * 60 + 30, 9 * 60 + 10),
    2: (9 * 60 + 20, 10 * 60),
    3: (10 * 60 + 20, 11 * 60),
    4: (11 * 60 + 10, 11 * 60 + 50),
    5: (14 * 60, 14 * 60 + 40),
    6: (14 * 60 + 50, 15 * 60 + 30),
    7: (15 * 60 + 40, 16 * 60 + 20),
    8: (16 * 60 + 30, 17 * 60 + 10),
    9: (19 * 60, 19 * 60 + 40),
    10: (19 * 60 + 50, 20 * 60 + 30),
    11: (20 * 60 + 40, 21 * 60 + 20),
  });
}
