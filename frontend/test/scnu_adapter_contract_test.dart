import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/services/scnu_html_preview.dart';
import 'package:student_life_rpg/features/academic/services/timetable_import.dart';
import 'package:student_life_rpg/features/academic/services/scnu_timetable_source.dart';
import 'package:student_life_rpg/features/academic/services/timetable_source.dart';
import 'package:student_life_rpg/features/timetable_capture/timetable_page_capture.dart';

class _SnapshotSession implements AuthenticatedPageSession {
  const _SnapshotSession(this.page);

  final PageSnapshot page;

  @override
  Future<PageSnapshot> openAndRead(
    Uri url, {
    required Duration timeout,
  }) async => page;
}

void main() {
  test('HTML adapter returns provider real TimetableParseResult', () {
    final html = File(
      'test/fixtures/issue34/scnu_deidentified.html',
    ).readAsStringSync();
    final TimetableParseResult result = parseScnuHtml(html, maxWeek: 17);
    expect(result.courses, isNotEmpty);
    expect(
      result.courses.every(
        (c) => !c.name.endsWith('*') && !c.name.endsWith('&'),
      ),
      isTrue,
    );
    expect(result.courses.expand((c) => c.slots).length, 22);
    expect(result.issues.any((i) => i.message.contains('其它课程')), isTrue);
    final java = result.courses.where((c) => c.name == 'JAVA语言程序设计').single;
    expect(java.credits, 4);
    expect(java.slots.length, 5);
  });

  test('official timetable snapshot reaches the production parser', () async {
    final url = Uri.https('jwxt.scnu.edu.cn', '/');
    final html = File(
      'test/fixtures/issue34/scnu_deidentified.html',
    ).readAsStringSync();
    final loader = ScnuTimetableHtmlLoader(
      _SnapshotSession(
        PageSnapshot(finalUrl: url, text: html, mimeType: 'text/html'),
      ),
    );
    final result = const ScnuTimetableHtmlParser().parse(
      await loader.load(url),
      maxWeek: 17,
    );
    expect(result.courses.expand((course) => course.slots).length, 22);
  });

  test('login and off-domain pages cannot become course previews', () async {
    final url = Uri.https('jwxt.scnu.edu.cn', '/');
    Future<void> expectRejected(Uri finalUrl, TimetableLoadError error) async {
      final loader = ScnuTimetableHtmlLoader(
        _SnapshotSession(
          PageSnapshot(
            finalUrl: finalUrl,
            text: '<input type="password">',
            mimeType: 'text/html',
          ),
        ),
      );
      await expectLater(
        loader.load(url),
        throwsA(
          isA<TimetableLoadException>().having((e) => e.error, 'error', error),
        ),
      );
    }

    await expectRejected(url, TimetableLoadError.loginExpired);
    await expectRejected(
      Uri.https('scnu.edu.cn.example.org', '/'),
      TimetableLoadError.unsupportedPage,
    );
  });
}
