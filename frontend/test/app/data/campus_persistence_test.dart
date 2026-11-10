import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/presentation/academic_editors.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';
import '../../support/campus_fixture.dart';

Semester semester([String id = 'fall']) => Semester(
  id: id,
  name: id,
  startDate: DateTime(2026, 10, 5),
  endDate: DateTime(2026, 12, 31),
  week1Monday: DateTime(2026, 10, 5),
);
Course course({
  String id = 'math',
  String semesterId = 'fall',
  double? point = 0,
}) => Course(
  id: id,
  semesterId: semesterId,
  name: id,
  credits: 3,
  gradePoint: point,
  scoreScaleMax: 4,
  slots: [
    CourseSlot(weekday: 1, startMinute: 540, endMinute: 600, weeks: [1, 3]),
  ],
);
Event event(String id) => Event(
  id: id,
  title: id,
  range: TimeRange(
    start: DateTime(2026, 10, 5, 9, 30),
    end: DateTime(2026, 10, 6, 1),
  ),
);

void main() {
  late Directory directory;
  late String path;
  CampusData open() =>
      CampusData(CampusStore(const FileJsonDocumentStore(), path));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('campus-data-');
    path = '${directory.path}/campus.json';
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'academic grades, event and finance survive new repository instances',
    () async {
      final data = open();
      await data.semesters.insert(semester());
      await data.courses.insert(course());
      await data.events.insert(event('meeting'));
      await data.records.insert(
        FinanceRecord(
          id: 'lunch',
          categoryId: 'food',
          type: FinanceType.expense,
          amountMinor: 1234,
          occurredAt: DateTime(2026, 10, 5, 12),
          note: '午餐',
        ),
      );
      final restored = open();
      expect(
        (await restored.semesters.list()).single.week1Monday,
        DateTime(2026, 10, 5),
      );
      expect((await restored.courses.list()).single.gradePoint, 0);
      expect(
        (await restored.gpa.loadGpa()).value,
        0,
        reason: 'Zero remains an eligible grade',
      );
      expect(
        (await restored.events.list()).single.range.end,
        DateTime(2026, 10, 6, 1),
      );
      final summary = await restored.financeService.loadMonth(
        DateTime(2026, 10),
      );
      expect(summary.expenseMinor, 1234);
      expect(
        summary.remainingBudgetMinor,
        isNull,
        reason: 'No fictitious budget',
      );
      expect((await restored.records.list()).single.note, '午餐');
      data.dispose();
      restored.dispose();
    },
  );

  test(
    'course recurrence uses semester boundaries, weekdays and actual week numbers',
    () async {
      final data = open();
      await data.semesters.insert(semester());
      await data.courses.insert(course());
      expect(await data.courseOccurrences(DateTime(2026, 10, 5)), hasLength(1));
      expect(await data.courseOccurrences(DateTime(2026, 10, 12)), isEmpty);
      expect(
        await data.courseOccurrences(DateTime(2026, 10, 19)),
        hasLength(1),
      );
      expect(await data.courseOccurrences(DateTime(2026, 10, 6)), isEmpty);
      expect(await data.courseOccurrences(DateTime(2026, 9, 28)), isEmpty);
      await data.events.insert(event('meeting'));
      final controller = DayScheduleController(
        loader: data.schedule(InMemoryTaskRepository()),
        initialDate: DateTime(2026, 10, 5),
      );
      await controller.loadDay();
      expect(controller.schedule!.items, hasLength(2));
      expect(controller.conflicts, hasLength(1));
      await controller.loadDay(DateTime(2026, 10, 6));
      expect(controller.schedule!.items.single.title, 'meeting');
      await data.events.remove('meeting');
      await controller.retry();
      expect(controller.schedule!.items, isEmpty);
      controller.dispose();
      data.dispose();
    },
  );

  test(
    'missing references and referenced deletions leave disk unchanged',
    () async {
      final data = open();
      await data.semesters.insert(semester());
      await data.courses.insert(course());
      final before = await File(path).readAsString();
      await expectLater(data.semesters.remove('fall'), throwsStateError);
      await expectLater(
        data.courses.insert(course(id: 'bad', semesterId: 'absent')),
        throwsStateError,
      );
      await expectLater(
        data.records.insert(
          FinanceRecord(
            id: 'bad',
            categoryId: 'food',
            type: FinanceType.income,
            amountMinor: 100,
            occurredAt: DateTime(2026, 10, 5),
          ),
        ),
        throwsStateError,
      );
      expect(await File(path).readAsString(), before);
      await data.courses.remove('math');
      await data.semesters.remove('fall');
      expect(await open().semesters.list(), isEmpty);
      data.dispose();
    },
  );

  test('finance edit and delete persist and update summary', () async {
    final data = open();
    await data.finance.load(month: DateTime.now());
    expect(
      await data.finance.addRecord(categoryId: 'food', amountText: '12.34'),
      isTrue,
    );
    final record = (await data.records.list()).single;
    expect(
      await data.finance.updateRecord(
        record.id,
        categoryId: 'allowance',
        amountText: '50.00',
        occurredAt: DateTime(2026, 11, 2),
        note: '改为收入',
      ),
      isTrue,
    );
    final restored = open();
    final summary = await restored.financeService.loadMonth(DateTime(2026, 11));
    expect(summary.incomeMinor, 5000);
    expect(summary.expenseMinor, 0);
    expect((await restored.records.list()).single.note, '改为收入');
    await expectLater(data.categories.remove('allowance'), throwsStateError);
    expect(await data.finance.removeRecord(record.id), isTrue);
    expect(await open().records.list(), isEmpty);
    data.dispose();
    restored.dispose();
  });

  test(
    'failed mutation never updates committed cache or disk; retry succeeds',
    () async {
      final documents = MemoryCampusDocuments();
      final data = CampusData(CampusStore(documents, 'test'));
      await data.semesters.insert(semester());
      final before = documents.documents['test'];
      documents.failWrites = true;
      await expectLater(data.courses.insert(course()), throwsStateError);
      expect(await data.courses.list(), isEmpty);
      expect(documents.documents['test'], before);
      documents.failWrites = false;
      await data.courses.insert(course());
      expect(await data.courses.list(), hasLength(1));
      data.dispose();
    },
  );

  test(
    'corruption rejects writes until explicit recovery and retains damaged original',
    () async {
      final data = open();
      await data.semesters.insert(semester());
      await data.courses.insert(course());
      final backup = await File('$path.bak').readAsString();
      await File(path).writeAsString('{damaged');
      await expectLater(
        data.events.insert(event('blocked')),
        throwsFormatException,
      );
      expect(await File(path).readAsString(), '{damaged');
      expect(await File('$path.bak').readAsString(), backup);
      final cold = open();
      await expectLater(cold.store.initialize(), throwsFormatException);
      await cold.store.recoverFromBackup();
      expect(await File('$path.corrupt').readAsString(), '{damaged');
      expect(await cold.semesters.list(), hasLength(1));
      expect(
        await cold.courses.list(),
        isEmpty,
        reason: 'The prior valid snapshot is restored explicitly',
      );
      await cold.events.insert(event('retry'));
      expect(await open().events.list(), hasLength(1));
      data.dispose();
      cold.dispose();
    },
  );

  test(
    'bad backup leaves damaged main intact and does not reset data',
    () async {
      await File(path).writeAsString('{bad');
      await File('$path.bak').writeAsString('{also bad');
      final data = open();
      await expectLater(data.store.recoverFromBackup(), throwsFormatException);
      expect(await File(path).readAsString(), '{bad');
      expect(await File('$path.bak').readAsString(), '{also bad');
      expect(await File('$path.corrupt').exists(), isFalse);
      data.dispose();
    },
  );

  test(
    'missing main with valid backup requires recovery, not empty initialization',
    () async {
      final data = open();
      await data.semesters.insert(semester());
      await data.courses.insert(course());
      await File(path).delete();
      final cold = open();
      await expectLater(cold.store.initialize(), throwsFormatException);
      await cold.store.recoverFromBackup();
      expect(await cold.semesters.list(), hasLength(1));
      data.dispose();
      cold.dispose();
    },
  );

  test(
    'concurrent duplicate inserts and different table writes do not lose data',
    () async {
      final data = open();
      await data.semesters.insert(semester());
      await Future.wait([
        data.courses.insert(course()),
        data.events.insert(event('parallel')),
      ]);
      final results = await Future.wait(
        List.generate(2, (_) async {
          try {
            await data.events.insert(event('duplicate'));
            return true;
          } on StateError {
            return false;
          }
        }),
      );
      expect(results.where((v) => v), hasLength(1));
      expect(await open().courses.list(), hasLength(1));
      expect(await open().events.list(), hasLength(2));
      data.dispose();
    },
  );

  test(
    'a stale open instance cannot overwrite a newer valid snapshot',
    () async {
      final first = open();
      await first.semesters.insert(semester());
      final second = open();
      await second.store.initialize();
      await first.events.insert(event('new'));
      await expectLater(second.events.insert(event('stale')), throwsStateError);
      expect((await open().events.list()).single.id, 'new');
      await second.store.recoverFromBackup();
      await second.events.insert(event('retry'));
      expect(await open().events.list(), hasLength(2));
      first.dispose();
      second.dispose();
    },
  );

  test(
    'strict schema rejects duplicate IDs, unknown fields and missing references',
    () async {
      final memory = MemoryCampusDocuments();
      final seed = CampusData(CampusStore(memory, 'seed'));
      await seed.semesters.insert(semester());
      await seed.courses.insert(course());
      final original = memory.documents['seed']!;
      for (final alter in <void Function(Map<String, dynamic>)>[
        (v) => v['schemaVersion'] = 99,
        (v) => v['extra'] = true,
        (v) => (v['courses'] as List).add((v['courses'] as List).first),
        (v) => (v['semesters'] as List).clear(),
        (v) => (v['courses'] as List).first['extra'] = true,
      ]) {
        final snapshot = jsonDecode(original) as Map<String, dynamic>;
        alter(snapshot);
        memory.documents['invalid'] = jsonEncode(snapshot);
        final candidate = CampusData(CampusStore(memory, 'invalid'));
        await expectLater(candidate.store.initialize(), throwsFormatException);
        candidate.dispose();
      }
      seed.dispose();
    },
  );

  test(
    'course form week and time parsers preserve valid midnight and reject bad ranges',
    () {
      expect(parseCourseWeeks('1-3,5,7'), [1, 2, 3, 5, 7]);
      for (final bad in ['', '3-1', '0', '1-3,3', '1-9999999', '1,x']) {
        expect(() => parseCourseWeeks(bad), throwsFormatException);
      }
      expect(parseCourseMinute('24:00', allowMidnight: true), 1440);
      for (final bad in ['24:00', '12:60', '99:00', '9.00']) {
        expect(() => parseCourseMinute(bad), throwsFormatException);
      }
    },
  );
}
