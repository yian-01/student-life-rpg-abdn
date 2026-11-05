import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/finance/models/budget.dart';
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

  Assignment newAssignment(
    String id, {
    String courseId = 'course-cs101',
    DateTime? dueAt,
  }) => Assignment(
    id: id,
    courseId: courseId,
    title: '作业$id',
    dueAt: dueAt ?? DateTime(2026, 11, 20, 23, 59),
  );

  Exam newExam(
    String id, {
    String courseId = 'course-cs101',
    DateTime? start,
  }) => Exam(
    id: id,
    courseId: courseId,
    title: '考试$id',
    range: TimeRange(
      start: start ?? DateTime(2026, 12, 20, 9, 0),
      end: (start ?? DateTime(2026, 12, 20, 9, 0)).add(
        const Duration(hours: 2),
      ),
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

  test('listForCourse 按时间排序：作业按 dueAt、考试按 range.start 升序', () async {
    await File(path).writeAsString(fixture);
    final data = open();

    // 故意打乱插入顺序
    await data.assignments.insert(
      newAssignment('late', dueAt: DateTime(2026, 12, 1)),
    );
    await data.assignments.insert(
      newAssignment('early', dueAt: DateTime(2026, 11, 10)),
    );
    await data.assignments.insert(
      newAssignment('mid', dueAt: DateTime(2026, 11, 20)),
    );
    await data.exams.insert(
      newExam('e-late', start: DateTime(2026, 12, 25, 9, 0)),
    );
    await data.exams.insert(
      newExam('e-early', start: DateTime(2026, 12, 10, 9, 0)),
    );

    expect(
      (await data.assignments.listForCourse('course-cs101')).map((a) => a.id),
      ['early', 'mid', 'late'],
    );
    expect(
      (await data.exams.listForCourse('course-cs101')).map((e) => e.id),
      ['e-early', 'e-late'],
    );

    // 重启后排序仍成立（排序不依赖内存中的插入顺序）
    final reopened = open();
    expect(
      (await reopened.assignments.listForCourse('course-cs101')).map(
        (a) => a.id,
      ),
      ['early', 'mid', 'late'],
    );
  });
}
