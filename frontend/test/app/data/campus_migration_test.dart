import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/finance/models/budget.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

/// CampusData v1 → v2 迁移测试。
///
/// fixture 固定为 fcab531 基线时代的 v1 文档结构（8 个顶层键、5 张表），
/// 迁移后原记录必须逐表逐值完整保留，新增 3 张表为空。
void main() {
  late Directory tempDir;
  late String path;
  late String fixture;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('campus_migration_test_');
    path = '${tempDir.path}/campus.json';
    fixture = await File(
      'test/app/data/fixtures/campus_v1_fixture.json',
    ).readAsString();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  CampusData open() =>
      CampusData(CampusStore(const FileJsonDocumentStore(), path));

  Assignment newAssignment(String id, {String courseId = 'course-cs101'}) =>
      Assignment(
        id: id,
        courseId: courseId,
        title: '作业$id',
        dueAt: DateTime(2026, 11, 20, 23, 59),
      );

  Exam newExam(String id, {String courseId = 'course-cs101'}) => Exam(
    id: id,
    courseId: courseId,
    title: '考试$id',
    range: TimeRange(
      start: DateTime(2026, 12, 20, 9, 0),
      end: DateTime(2026, 12, 20, 11, 0),
    ),
  );

  Budget newBudget({
    String categoryId = 'food',
    DateTime? month,
    int amountMinor = 50000,
  }) => Budget(
    categoryId: categoryId,
    month: month ?? DateTime(2026, 11),
    amountMinor: amountMinor,
  );

  test('v1 文档自动升级为 v2，原记录逐表完整保留', () async {
    await File(path).writeAsString(fixture);

    final data = open();
    await data.store.initialize();

    // 原记录逐表完整：学期/课程/分类/账目数量与关键值不变
    expect((await data.semesters.list()).length, 1);
    expect((await data.semesters.list()).first.name, '2026 秋季学期');
    expect((await data.courses.list()).length, 1);
    expect((await data.courses.list()).first.credits, 3);
    expect((await data.courses.list()).first.gradePoint, isNull);
    expect((await data.categories.list()).length, 5);
    expect((await data.records.list()).length, 1);
    expect((await data.records.list()).first.amountMinor, 1250);
    expect(await data.events.list(), isEmpty);
    // 新表为空
    expect(await data.assignments.list(), isEmpty);
    expect(await data.exams.list(), isEmpty);
    expect(await data.budgets.list(), isEmpty);

    // 磁盘文件已写回 v2；旧版 v1 自动留存为 .bak
    final upgraded =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    expect(upgraded['schemaVersion'], 2);
    expect(upgraded['assignments'], isEmpty);
    expect(upgraded['exams'], isEmpty);
    expect(upgraded['budgets'], isEmpty);
    expect(await File('$path.bak').readAsString(), fixture);
  });

  test('升级后可插入作业/考试/预算并重启后保留', () async {
    await File(path).writeAsString(fixture);

    final data = open();
    await data.assignments.insert(newAssignment('a1'));
    await data.exams.insert(newExam('e1'));
    await data.budgets.put(newBudget());

    expect((await data.assignments.listForCourse('course-cs101')).length, 1);
    expect((await data.exams.listForCourse('course-cs101')).length, 1);
    expect((await data.budgets.list()).length, 1);
    expect(
      (await data.budgets.getForCategoryMonth(
        'food',
        DateTime(2026, 11),
      ))?.amountMinor,
      50000,
    );

    // 重新创建实例，从磁盘读回，验证持久化
    final reopened = open();
    expect((await reopened.assignments.list()).single.title, '作业a1');
    expect((await reopened.exams.list()).single.title, '考试e1');
    expect((await reopened.budgets.list()).single.amountMinor, 50000);
  });

  test('引用保护：作业/考试必须指向已存在课程，预算必须指向支出分类', () async {
    await File(path).writeAsString(fixture);
    final data = open();

    await expectLater(
      data.assignments.insert(newAssignment('bad', courseId: 'no-course')),
      throwsStateError,
    );
    await expectLater(
      data.exams.insert(newExam('bad', courseId: 'no-course')),
      throwsStateError,
    );
    await expectLater(
      data.budgets.put(newBudget(categoryId: 'no-category')),
      throwsStateError,
    );
    // 收入分类不能建预算
    await expectLater(
      data.budgets.put(newBudget(categoryId: 'allowance')),
      throwsStateError,
    );

    // 同一类别+月份只有一行：重复 put 为替换，不产生第二行
    await data.budgets.put(newBudget());
    await data.budgets.put(newBudget(amountMinor: 60000));
    expect(await data.budgets.list(), hasLength(1));
    expect((await data.budgets.list()).single.amountMinor, 60000);
    // 同分类不同月份允许
    await data.budgets.put(newBudget(month: DateTime(2026, 12)));

    // 删除仍被作业引用的课程被拒绝
    await data.assignments.insert(newAssignment('a1'));
    await expectLater(data.courses.remove('course-cs101'), throwsStateError);
    // 删除仍被预算引用的分类被拒绝
    await expectLater(data.categories.remove('food'), throwsStateError);

    // 被阻止的写入不落盘：重启后新表仍为本次成功写入的记录
    final reopened = open();
    expect(await reopened.assignments.list(), hasLength(1));
    expect(await reopened.budgets.list(), hasLength(2));
  });

  test('未知未来 schema 与未知顶层键被拒绝', () async {
    final v2 = jsonDecode(fixture) as Map<String, dynamic>;
    v2['schemaVersion'] = 99;
    v2['assignments'] = [];
    v2['exams'] = [];
    v2['budgets'] = [];
    await File(path).writeAsString(jsonEncode(v2));
    await expectLater(
      open().store.initialize(),
      throwsA(isA<FormatException>()),
    );

    final extra = jsonDecode(fixture) as Map<String, dynamic>;
    extra['unknownFutureTable'] = [];
    await File(path).writeAsString(jsonEncode(extra));
    await expectLater(
      open().store.initialize(),
      throwsA(isA<FormatException>()),
    );
    // 拒绝不吞数据：文件内容保持不变
    expect(
      (jsonDecode(await File(path).readAsString())
          as Map<String, dynamic>)['unknownFutureTable'],
      isNotNull,
    );
  });

  test('预算行 id 必须等于唯一键，否则拒绝加载', () async {
    final v2 = jsonDecode(fixture) as Map<String, dynamic>;
    v2['schemaVersion'] = 2;
    v2['assignments'] = [];
    v2['exams'] = [];
    v2['budgets'] = [
      {
        'id': 'food@2026-11-wrong',
        'categoryId': 'food',
        'month': '2026-11-01',
        'amountMinor': 1000,
      },
    ];
    await File(path).writeAsString(jsonEncode(v2));

    await expectLater(
      open().store.initialize(),
      throwsA(isA<FormatException>()),
    );
  });

  test('预算行缺少 id 时抛 FormatException 而不是类型错误', () async {
    final v2 = jsonDecode(fixture) as Map<String, dynamic>;
    v2['schemaVersion'] = 2;
    v2['assignments'] = [];
    v2['exams'] = [];
    v2['budgets'] = [
      {'categoryId': 'food', 'month': '2026-11-01', 'amountMinor': 1000},
    ];
    await File(path).writeAsString(jsonEncode(v2));

    await expectLater(
      open().store.initialize(),
      throwsA(isA<FormatException>()),
    );
  });

  // ---------- 原子批量写入 ----------
  List<Map<String, dynamic>> newCourses({int count = 3, String? semester}) => [
    for (var i = 1; i <= count; i++)
      Course(
        id: 'import-$i',
        semesterId: semester ?? 'sem-2026-autumn',
        name: '导入课程$i',
        credits: 2,
        gradePoint: null,
        slots: const [],
        scoreScaleMax: 4.0,
      ).toJson(),
  ];

  test('批量写入课程整批成功并持久化', () async {
    await File(path).writeAsString(fixture);
    final store = CampusStore(const FileJsonDocumentStore(), path);
    await store.initialize();

    final result = await store.applyBatch([
      CampusBatch(table: 'courses', rows: newCourses()),
    ]);
    expect(result.inserted, 3);
    expect(result.updated, 0);

    final reopened = CampusData(
      CampusStore(const FileJsonDocumentStore(), path),
    );
    expect((await reopened.courses.list()).length, 4); // fixture 1 + 新增 3
  });

  test('批量中任一行非法时整批零提交', () async {
    await File(path).writeAsString(fixture);
    final store = CampusStore(const FileJsonDocumentStore(), path);
    final data = CampusData(store);
    await store.initialize();
    final before = await File(path).readAsString();

    // 第 2 门课程引用不存在的学期 → 整批失败
    await expectLater(
      store.applyBatch([
        CampusBatch(
          table: 'courses',
          rows: newCourses(semester: 'missing-semester'),
        ),
      ]),
      throwsStateError,
    );
    expect(await File(path).readAsString(), before);
    expect((await data.courses.list()).length, 1);
  });

  test('重复导入同 id 为更新而不是新增', () async {
    await File(path).writeAsString(fixture);
    final store = CampusStore(const FileJsonDocumentStore(), path);
    await store.initialize();
    await store.applyBatch([CampusBatch(table: 'courses', rows: newCourses())]);

    final result = await store.applyBatch([
      CampusBatch(table: 'courses', rows: newCourses()),
    ]);
    expect(result.inserted, 0);
    expect(result.updated, 3);
    expect((await store.rows('courses')).length, 4);
  });

  test('批内重复 id 整批拒绝', () async {
    await File(path).writeAsString(fixture);
    final store = CampusStore(const FileJsonDocumentStore(), path);
    await store.initialize();
    final before = await File(path).readAsString();

    final rows = newCourses(count: 2);
    rows[1]['id'] = rows[0]['id'];
    await expectLater(
      store.applyBatch([CampusBatch(table: 'courses', rows: rows)]),
      throwsStateError,
    );
    expect(await File(path).readAsString(), before);
  });

  test('全部实体写入后重新创建实例，逐表完整保留', () async {
    await File(path).writeAsString(fixture);
    final data = open();
    await data.store.initialize();

    await data.semesters.insert(
      Semester(
        id: 'sem-2027-spring',
        name: '2027 春季学期',
        startDate: DateTime(2027, 2, 22),
        endDate: DateTime(2027, 6, 30),
        week1Monday: DateTime(2027, 2, 22),
      ),
    );
    await data.courses.insert(
      Course(
        id: 'course-new',
        semesterId: 'sem-2027-spring',
        name: '数据结构',
        credits: 2.5,
        gradePoint: null,
        slots: [
          CourseSlot(
            weekday: 3,
            startMinute: 480,
            endMinute: 570,
            weeks: const [1, 2, 3, 4],
          ),
        ],
        scoreScaleMax: 4.0,
      ),
    );
    await data.assignments.insert(
      Assignment(
        id: 'a-new',
        courseId: 'course-new',
        title: '实验一',
        dueAt: DateTime(2027, 3, 1, 23, 59),
      ),
    );
    await data.exams.insert(
      Exam(
        id: 'e-new',
        courseId: 'course-new',
        title: '期中考试',
        range: TimeRange(
          start: DateTime(2027, 4, 10, 9, 0),
          end: DateTime(2027, 4, 10, 11, 0),
        ),
      ),
    );
    await data.events.insert(
      Event(
        id: 'ev-new',
        title: '社团活动',
        range: TimeRange(
          start: DateTime(2027, 3, 5, 14, 0),
          end: DateTime(2027, 3, 5, 16, 0),
        ),
        description: '例会',
      ),
    );
    await data.categories.insert(
      FinanceCategory(id: 'study', name: '学习', type: FinanceType.expense),
    );
    await data.records.insert(
      FinanceRecord(
        id: 'rec-new',
        categoryId: 'study',
        type: FinanceType.expense,
        amountMinor: 3500,
        occurredAt: DateTime(2027, 3, 2, 18, 30),
        note: '教材',
      ),
    );
    await data.budgets.put(
      Budget(categoryId: 'study', month: DateTime(2027, 3), amountMinor: 10000),
    );

    // 完全丢弃旧实例，只从磁盘重新读取。
    final reopened = open();
    final storedSemester = await reopened.semesters.getById('sem-2027-spring');
    expect(storedSemester?.name, '2027 春季学期');
    expect(storedSemester?.week1Monday, DateTime(2027, 2, 22));

    final storedCourse = await reopened.courses.getById('course-new');
    expect(storedCourse?.name, '数据结构');
    expect(storedCourse?.credits, 2.5);
    expect(storedCourse?.semesterId, 'sem-2027-spring');
    expect(storedCourse?.slots.single.weeks, const [1, 2, 3, 4]);

    expect((await reopened.assignments.getById('a-new'))?.title, '实验一');
    expect((await reopened.exams.getById('e-new'))?.title, '期中考试');
    expect((await reopened.events.getById('ev-new'))?.description, '例会');
    expect(
      (await reopened.categories.getById('study'))?.type,
      FinanceType.expense,
    );
    expect((await reopened.records.getById('rec-new'))?.note, '教材');
    expect(
      (await reopened.budgets.getForCategoryMonth(
        'study',
        DateTime(2027, 3),
      ))?.amountMinor,
      10000,
    );
  });
}
