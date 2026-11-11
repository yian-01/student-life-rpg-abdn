import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/services/scnu_html_preview.dart';
import 'package:student_life_rpg/features/academic/services/timetable_import.dart';
import 'package:student_life_rpg/features/academic/services/timetable_import_plan.dart';
import 'package:student_life_rpg/features/academic/services/scnu_timetable_source.dart';
import 'package:student_life_rpg/features/academic/services/timetable_source.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/features/timetable_capture/timetable_page_capture.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

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

  test('SCNU import survives reopen and reaches the schedule', () async {
    final directory = await Directory.systemTemp.createTemp('scnu-import-');
    addTearDown(() => directory.delete(recursive: true));
    const documents = FileJsonDocumentStore();
    final campusPath = '${directory.path}/campus.json';
    final data = CampusData(CampusStore(documents, campusPath));
    addTearDown(data.dispose);
    final monday = DateTime(2026, 9, 7);
    final semester = Semester(
      id: 'scnu-term',
      name: '华师导入回归',
      startDate: monday,
      endDate: DateTime(2027, 1, 3),
      week1Monday: monday,
    );
    await data.semesters.insert(semester);
    final url = Uri.https('jwxt.scnu.edu.cn', '/');
    final html = File(
      'test/fixtures/issue34/scnu_deidentified.html',
    ).readAsStringSync();
    final loader = ScnuTimetableHtmlLoader(
      _SnapshotSession(
        PageSnapshot(finalUrl: url, text: html, mimeType: 'text/html'),
      ),
    );
    final parsed = const ScnuTimetableHtmlParser().parse(
      await loader.load(url),
      maxWeek: semester.lastValidWeek,
    );
    final preview = buildImportPlan(
      parsed: parsed,
      existingCourses: await data.courses.list(),
      semesterId: semester.id,
      scoreScaleMax: CampusStore.scoreScaleMax,
    );
    expect(await data.courses.list(), isEmpty);
    final selected = coursesFromPlan(
      preview,
      scoreScaleMax: CampusStore.scoreScaleMax,
    );
    final result = await data.store.applyBatch([
      CampusBatch(
        table: 'courses',
        rows: [for (final course in selected) course.toJson()],
      ),
    ]);
    expect(result, (inserted: selected.length, updated: 0));

    final reopened = CampusData(CampusStore(documents, campusPath));
    addTearDown(reopened.dispose);
    final saved = await reopened.courses.list();
    expect(saved, hasLength(selected.length));
    final java = saved.singleWhere((course) => course.name == 'JAVA语言程序设计');
    expect(java.credits, 4);
    expect(java.gradePoint, isNull);
    final slot = java.slots.first;
    final date = DateTime(
      monday.year,
      monday.month,
      monday.day + (slot.weeks.first - 1) * 7 + slot.weekday - 1,
    );
    final tasks = FileTaskRepository(documents, '${directory.path}/tasks.json');
    final schedule = await reopened.schedule(tasks).loadDay(date);
    expect(schedule.errors, isEmpty);
    expect(
      schedule.items.any(
        (item) =>
            item.sourceType == ScheduleSourceType.course &&
            item.sourceId == java.id &&
            item.range.start.hour * 60 + item.range.start.minute ==
                slot.startMinute,
      ),
      isTrue,
    );
    final repeated = buildImportPlan(
      parsed: parsed,
      existingCourses: saved,
      semesterId: semester.id,
      scoreScaleMax: CampusStore.scoreScaleMax,
    );
    expect(repeated.unchangedCount, saved.length);
    expect(repeated.pending, isEmpty);
  });
}
