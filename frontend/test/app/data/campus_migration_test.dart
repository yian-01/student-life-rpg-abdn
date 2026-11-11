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

  /// fixture 升级后的 v2 文档，供恢复类用例直接写盘。
  String v2Doc() {
    final doc = jsonDecode(fixture) as Map<String, dynamic>;
    doc['schemaVersion'] = 2;
    doc['assignments'] = <dynamic>[];
    doc['exams'] = <dynamic>[];
    doc['budgets'] = <dynamic>[];
    return jsonEncode(doc);
  }

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

  test('有效空 records：空数组可正常读取并升级为 v2', () async {
    final doc = jsonDecode(fixture) as Map<String, dynamic>;
    doc['records'] = <dynamic>[];
    doc['events'] = <dynamic>[];
    await File(path).writeAsString(jsonEncode(doc));

    final data = open();
    await data.store.initialize();

    expect(await data.records.list(), isEmpty);
    expect(await data.events.list(), isEmpty);
    expect((await data.courses.list()).length, 1);

    final upgraded =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    expect(upgraded['schemaVersion'], 2);
    expect(upgraded['records'], isEmpty);
  });

  test('v1 升级保留零绩点，且与未评分可区分；整数金额不丢精度', () async {
    final doc = jsonDecode(fixture) as Map<String, dynamic>;
    (doc['courses'] as List).add({
      'id': 'course-ma101',
      'semesterId': 'sem-2026-autumn',
      'name': '高等数学',
      'credits': 4,
      'gradePoint': 0,
      'slots': <dynamic>[],
    });
    await File(path).writeAsString(jsonEncode(doc));

    final data = open();
    await data.store.initialize();

    final courses = await data.courses.list();
    final zero = courses.firstWhere((c) => c.id == 'course-ma101');
    expect(zero.gradePoint, 0.0);
    // 零绩点与未评分必须可区分，不能被统一成 null
    final ungraded = courses.firstWhere((c) => c.id == 'course-cs101');
    expect(ungraded.gradePoint, isNull);

    // 金额以最小货币单位按整数保留，迁移不得退化为浮点
    final record = (await data.records.list()).single;
    expect(record.amountMinor, 1250);
  });

  test('跨日考试的时间范围在重开后完整保留', () async {
    await File(path).writeAsString(fixture);
    final data = open();
    await data.exams.insert(
      Exam(
        id: 'e-cross',
        courseId: 'course-cs101',
        title: '跨日考试',
        range: TimeRange(
          start: DateTime(2026, 12, 20, 23, 0),
          end: DateTime(2026, 12, 21, 1, 0),
        ),
      ),
    );

    final reopened = open();
    final exam = (await reopened.exams.list()).single;
    expect(exam.range.start, DateTime(2026, 12, 20, 23, 0));
    expect(exam.range.end, DateTime(2026, 12, 21, 1, 0));
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

  // ---------- 恢复与负向回归 ----------
  test('主文件损坏且备份有效时，普通读取报错，显式恢复写回并归档原件', () async {
    const broken = '{"entityType":';
    final valid = v2Doc();
    await File(path).writeAsString(broken);
    await File('$path.bak').writeAsString(valid);
    final store = CampusStore(const FileJsonDocumentStore(), path);

    await expectLater(store.initialize(), throwsA(isA<FormatException>()));
    expect(await File(path).readAsString(), broken);
    expect(File('$path.corrupt').existsSync(), isFalse);

    await store.recoverFromBackup();
    expect(await File(path).readAsString(), valid);
    expect(await File('$path.corrupt').readAsString(), broken);
    expect((await store.rows('courses')).length, 1);
  });

  test('备份也损坏时显式恢复被拒绝，不覆盖主文件也不产生归档', () async {
    const broken = '{"entityType":';
    const brokenBackup = '{"schemaVersion":';
    await File(path).writeAsString(broken);
    await File('$path.bak').writeAsString(brokenBackup);
    final store = CampusStore(const FileJsonDocumentStore(), path);

    await expectLater(store.initialize(), throwsA(isA<FormatException>()));
    await expectLater(
      store.recoverFromBackup(),
      throwsA(isA<FormatException>()),
    );
    expect(await File(path).readAsString(), broken);
    expect(await File('$path.bak').readAsString(), brokenBackup);
    expect(File('$path.corrupt').existsSync(), isFalse);
  });

  test('主文件缺失但备份存在时读取报错，显式恢复后才可用', () async {
    await File('$path.bak').writeAsString(v2Doc());
    final store = CampusStore(const FileJsonDocumentStore(), path);

    await expectLater(store.rows('courses'), throwsA(isA<FormatException>()));
    expect(File(path).existsSync(), isFalse);

    await store.recoverFromBackup();
    expect((await store.rows('courses')).length, 1);
  });

  test('v1 升级写回失败时不改动原文件，解除阻塞后可重试', () async {
    await File(path).writeAsString(fixture);
    // 用目录占用临时文件路径，让升级写回在第一步就失败。
    await Directory('$path.tmp').create();
    final store = CampusStore(const FileJsonDocumentStore(), path);

    await expectLater(store.initialize(), throwsA(isA<FileSystemException>()));
    expect(await File(path).readAsString(), fixture);
    expect(File('$path.bak').existsSync(), isFalse);

    await Directory('$path.tmp').delete();
    final reopened = CampusStore(const FileJsonDocumentStore(), path);
    await reopened.initialize();
    expect((await reopened.rows('courses')).length, 1);
    final upgraded =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    expect(upgraded['schemaVersion'], 2);
    expect(await File('$path.bak').readAsString(), fixture);
  });

  test('缓存后主文件被外部修改时拒绝写入，显式恢复采用外部数据', () async {
    await File(path).writeAsString(v2Doc());
    final store = CampusStore(const FileJsonDocumentStore(), path);
    await store.initialize();

    final external =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    (external['courses'] as List).add(
      Course(
        id: 'ext-course',
        semesterId: 'sem-2026-autumn',
        name: '外部课程',
        credits: 2,
        gradePoint: null,
        slots: const [],
        scoreScaleMax: 4.0,
      ).toJson(),
    );
    await File(path).writeAsString(jsonEncode(external));

    await expectLater(
      store.mutate(
        'courses',
        'blocked',
        Course(
          id: 'blocked',
          semesterId: 'sem-2026-autumn',
          name: '冲突课程',
          credits: 2,
          gradePoint: null,
          slots: const [],
          scoreScaleMax: 4.0,
        ).toJson(),
        'insert',
      ),
      throwsStateError,
    );
    expect(await File(path).readAsString(), jsonEncode(external));

    await store.recoverFromBackup();
    final rows = await store.rows('courses');
    expect(rows.any((row) => row['id'] == 'ext-course'), isTrue);
    expect(rows.any((row) => row['id'] == 'blocked'), isFalse);
  });

  test('归档路径已存在时递增命名，不覆盖旧归档', () async {
    const broken = '{"entityType":';
    final valid = v2Doc();
    await File(path).writeAsString(broken);
    await File('$path.bak').writeAsString(valid);
    await File('$path.corrupt').writeAsString('previous archive');
    final store = CampusStore(const FileJsonDocumentStore(), path);

    await store.recoverFromBackup();
    expect(await File(path).readAsString(), valid);
    expect(await File('$path.corrupt').readAsString(), 'previous archive');
    expect(await File('$path.corrupt.1').readAsString(), broken);
  });

  test('主文件损坏且完全无备份时，显式恢复抛异常且原件保留', () async {
    const broken = '{"entityType":';
    await File(path).writeAsString(broken);
    // 确保没有 .bak
    final bak = File('$path.bak');
    if (await bak.exists()) await bak.delete();

    final store = CampusStore(const FileJsonDocumentStore(), path);
    // 普通读取报错
    await expectLater(store.rows('courses'), throwsA(isA<FormatException>()));
    // 显式恢复也报错，且原件不动
    await expectLater(
      store.recoverFromBackup(),
      throwsA(isA<FormatException>()),
    );
    expect(await File(path).readAsString(), broken);
    expect(await File('$path.corrupt').exists(), isFalse);
    expect(await File('$path.bak').exists(), isFalse);
  });

  test('并发批量写入按队列串行执行，不丢任何一批', () async {
    await File(path).writeAsString(v2Doc());
    final store = CampusStore(const FileJsonDocumentStore(), path);
    await store.initialize();

    final results = await Future.wait([
      store.applyBatch([CampusBatch(table: 'courses', rows: newCourses())]),
      store.applyBatch([
        CampusBatch(
          table: 'courses',
          rows: [
            Course(
              id: 'import-4',
              semesterId: 'sem-2026-autumn',
              name: '导入课程4',
              credits: 3,
              gradePoint: null,
              slots: const [],
              scoreScaleMax: 4.0,
            ).toJson(),
          ],
        ),
      ]),
    ]);
    expect(results[0].inserted, 3);
    expect(results[1].inserted, 1);
    expect((await store.rows('courses')).length, 5); // fixture 1 + 3 + 1
  });
}
