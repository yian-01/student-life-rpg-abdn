/// Source-normalization primitive, independent of preview/storage contracts.
/// The caller supplies a confirmed semester bound, never an inferred 17 weeks.
List<int> parseTimetableWeeks(String text, {required int maxWeek}) {
  if (maxWeek < 1) throw ArgumentError.value(maxWeek, 'maxWeek');
  var input = text.trim().replaceAll('，', ',');
  final odd = input.contains('单');
  final even = input.contains('双');
  if (odd && even) throw const FormatException('Conflicting week parity.');
  input = input
      .replaceAll(RegExp(r'\([单双]周?\)|（[单双]周?）'), '')
      .replaceAll('周', '');
  if (!RegExp(r'^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$').hasMatch(input)) {
    throw const FormatException('Unsupported week expression.');
  }
  final weeks = <int>{};
  for (final part in input.split(',')) {
    final endpoints = part.split('-').map(int.parse).toList();
    final start = endpoints.first;
    final end = endpoints.last;
    if (start < 1 || end < start || end > maxWeek) {
      throw const FormatException('Week outside confirmed semester bounds.');
    }
    for (var week = start; week <= end; week++) {
      if (odd && week.isEven || even && week.isOdd) continue;
      if (!weeks.add(week)) throw const FormatException('Duplicate week.');
    }
  }
  if (weeks.isEmpty) throw const FormatException('No applicable weeks.');
  return List.unmodifiable(weeks.toList()..sort());
}
