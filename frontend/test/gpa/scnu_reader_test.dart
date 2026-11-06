import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/gpa/services/scnu_timetable_reader.dart';

String sample({
  String week = '1-4周,6周',
  String credits = '2.0',
  String identity = 'synthetic-class',
}) =>
    '''
<table id="kbgrid_table_0"><tr><td id="2-1"><div class="timetable_con text-left">
<span class="title"><font>合成课程*</font></span>
<p><span title="节/周"></span><font>(1-2节)$week</font></p>
<p><span title="教学班名称"></span><font>$identity</font></p>
<p><span title="上课地点"></span><font>合成教室</font></p>
<p><span title="教师 "></span><font>合成教师</font></p>
<p><span title="学分"></span><font>$credits</font></p>
</div></td></tr></table>''';

void main() {
  final reader = ScnuTimetableReader();
  const periods = {1: (start: 510, end: 550), 2: (start: 560, end: 600)};
  test('SCNU captured layout yields source preview without writing Course', () {
    final rows = reader.read(sample(), periods: periods, maxWeek: 6);
    final row = rows.single;
    expect(row.weekday, 2);
    expect(row.weeks, [1, 2, 3, 4, 6]);
    expect(row.startMinute, 510);
    expect(row.endMinute, 600);
    expect(row.credits, 2);
    expect(row.location, '合成教室');
    expect(row.teacher, '合成教师');
    expect(row.sourceId, 'scnu:synthetic-class');
    expect(() => rows.clear(), throwsUnsupportedError);
  });
  test('missing credits stays null rather than fabricated default', () {
    final row = reader
        .read(sample(credits: ''), periods: periods, maxWeek: 6)
        .single;
    expect(row.credits, isNull);
    expect(row.missingFields, contains('credits'));
  });
  test(
    'login, empty, invalid fields, identity and period failures are visible',
    () {
      for (final html in [
        '<form>登录</form>',
        '<table id="kbgrid_table_0"></table>',
        sample(week: '1-999周'),
        sample(credits: 'NaN'),
        sample(identity: ''),
      ]) {
        expect(
          () => reader.read(html, periods: periods, maxWeek: 6),
          throwsFormatException,
        );
      }
      expect(
        () => reader.read(sample(), periods: {}, maxWeek: 6),
        throwsFormatException,
      );
    },
  );
}
