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

  Budget newBudget(
    String id, {
    String categoryId = 'food',
    String month = '2026-11',
    int limitMinor = 50000,
  }) => Budget(
    id: id,
    categoryId: categoryId,
    month: month,
    limitMinor: limitMinor,
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
    await data.budgets.insert(newBudget('b1'));

    expect((await data.assignments.listForCourse('course-cs101')).length, 1);
    expect((await data.exams.listForCourse('course-cs101')).length, 1);
    expect((await data.budgets.listForMonth('2026-11')).length, 1);
    expect(
      (await data.budgets.forCategoryMonth('food', '2026-11'))?.limitMinor,
      50000,
    );

    // 重新创建实例，从磁盘读回，验证持久化
    final reopened = open();
    expect((await reopened.assignments.list()).single.title, '作业a1');
    expect((await reopened.exams.list()).single.title, '考试e1');
    expect((await reopened.budgets.list()).single.limitMinor, 50000);
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
      data.budgets.insert(newBudget('bad', categoryId: 'no-category')),
      throwsStateError,
    );
    // 收入分类不能建预算
    await expectLater(
      data.budgets.insert(newBudget('bad-income', categoryId: 'allowance')),
      throwsStateError,
    );

    // (categoryId, month) 组合唯一
    await data.budgets.insert(newBudget('b1'));
    await expectLater(data.budgets.insert(newBudget('b2')), throwsStateError);
    // 同分类不同月份允许
    await data.budgets.insert(newBudget('b3', month: '2026-12'));

    // 删除仍被作业引用的课程被拒绝
    await data.assignments.insert(newAssignment('a1'));
    await expectLater(data.courses.remove('course-cs101'), throwsStateError);
    // 删除仍被预算引用的分类被拒绝
    await expectLater(data.categories.remove('food'), throwsStateError);

    // 被阻止的写入不落盘：重启后新表仍为空
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
}
