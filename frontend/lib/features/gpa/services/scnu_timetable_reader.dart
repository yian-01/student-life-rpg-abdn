import 'timetable_weeks.dart';

/// Source-only preview row, NOT a Course or a storage/save contract.
typedef ScnuTimetableRow = ({
  String sourceId,
  String name,
  int weekday,
  List<int> weeks,
  int startMinute,
  int endMinute,
  String? location,
  String? teacher,
  double? credits,
  List<String> missingFields,
});

/// Supports the captured SCNU kbgrid_table_0 HTML layout only.
/// Never executes scripts, logs in, fetches URLs or writes any repository.
class ScnuTimetableReader {
  List<ScnuTimetableRow> read(
    String html, {
    required Map<int, ({int start, int end})> periods,
    required int maxWeek,
  }) {
    if (maxWeek < 1) throw ArgumentError.value(maxWeek, 'maxWeek');
    final table = RegExp(
      r'''<table\b[^>]*\bid=["']kbgrid_table_0["'][^>]*>([\s\S]*?)</table>''',
      caseSensitive: false,
    ).firstMatch(html);
    if (table == null) {
      throw const FormatException(
        'Unsupported page or expired login; SCNU grid missing.',
      );
    }
    final result = <ScnuTimetableRow>[];
    final seen = <String>{};
    for (final cell in RegExp(
      r'<td\b([^>]*)>([\s\S]*?)</td>',
      caseSensitive: false,
    ).allMatches(table.group(1)!)) {
      final body = cell.group(2)!;
      if (!body.contains('timetable_con')) continue;
      final position = RegExp(
        r'''\bid=["']([1-7])-([0-9]+)["']''',
      ).firstMatch(cell.group(1)!);
      if (position == null) {
        throw const FormatException('Missing weekday/period cell.');
      }
      final weekday = int.parse(position.group(1)!);
      final blocks = body
          .split(
            RegExp(r'''<div\b[^>]*class=["']timetable_con[^"']*["'][^>]*>'''),
          )
          .skip(1);
      for (final block in blocks) {
        final title = RegExp(
          r'''<(?:span|u)\b[^>]*class=["']title[^"']*["'][^>]*>([\s\S]*?)</(?:span|u)>''',
        ).firstMatch(block);
        if (title == null) throw const FormatException('Missing course title.');
        final name = _text(title.group(1)!);
        String? field(String label) {
          for (final p in RegExp(
            r'<p\b[^>]*>([\s\S]*?)</p>',
          ).allMatches(block)) {
            if (RegExp(
              'title=["\x27]${RegExp.escape(label)}\\s*["\x27]',
            ).hasMatch(p.group(1)!)) {
              return _text(p.group(1)!);
            }
          }
          return null;
        }

        final schedule = field('节/周');
        final time = schedule == null
            ? null
            : RegExp(
                r'^\((\d+)-(\d+)节\)(.+)$',
              ).firstMatch(schedule.replaceAll(' ', ''));
        if (name.isEmpty || time == null) {
          throw const FormatException(
            'Missing or unsupported course schedule.',
          );
        }
        final first = int.parse(time.group(1)!);
        final last = int.parse(time.group(2)!);
        if (first > last || first != int.parse(position.group(2)!)) {
          throw const FormatException('Inconsistent period information.');
        }
        var previousEnd = -1;
        for (var period = first; period <= last; period++) {
          final mapped = periods[period];
          if (mapped == null ||
              mapped.start < 0 ||
              mapped.end > 1440 ||
              mapped.start >= mapped.end ||
              mapped.start < previousEnd) {
            throw const FormatException(
              'Missing or invalid period time mapping.',
            );
          }
          previousEnd = mapped.end;
        }
        final weeks = parseTimetableWeeks(time.group(3)!, maxWeek: maxWeek);
        final identity = field('教学班名称');
        if (identity == null || identity.isEmpty) {
          throw const FormatException(
            'Source class identity missing; do not merge by name.',
          );
        }
        final creditsText = field('学分');
        final credits = creditsText == null || creditsText.isEmpty
            ? null
            : double.tryParse(creditsText);
        if (creditsText != null &&
            creditsText.isNotEmpty &&
            (credits == null || !credits.isFinite || credits <= 0)) {
          throw const FormatException('Invalid source credits.');
        }
        final location = field('上课地点');
        final teacher = field('教师');
        final sourceId = 'scnu:${Uri.encodeComponent(identity)}';
        final key =
            '$sourceId/$weekday/$first/$last/${weeks.join(',')}/${location ?? ''}';
        if (!seen.add(key)) {
          throw const FormatException('Duplicate source occurrence.');
        }
        result.add((
          sourceId: sourceId,
          name: name,
          weekday: weekday,
          weeks: weeks,
          startMinute: periods[first]!.start,
          endMinute: periods[last]!.end,
          location: location,
          teacher: teacher,
          credits: credits,
          missingFields: List.unmodifiable([
            if (credits == null) 'credits',
            if (location == null || location.isEmpty) 'location',
            if (teacher == null || teacher.isEmpty) 'teacher',
          ]),
        ));
      }
    }
    if (result.isEmpty) {
      throw const FormatException(
        'Empty timetable requires explicit user confirmation.',
      );
    }
    if (table.group(1)!.contains('其它课程')) {
      throw const FormatException(
        'Unscheduled other courses need preview handling; refusing partial success.',
      );
    }
    return List.unmodifiable(result);
  }
}

String _text(String value) => value
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
