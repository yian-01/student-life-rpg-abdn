import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/presentation/assignment_exam_page.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import '../support/in_memory_academic_repositories.dart';

/// 把编辑器当作真实对话框弹出来，验证保存/取消的记录行为。
Future<BuildContext> _host(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (inner) {
          context = inner;
          return const Scaffold(body: SizedBox());
        },
      ),
    ),
  );
  return context;
}

void main() {
  testWidgets('作业编辑器：保存写入仓库，取消不写入', (tester) async {
    final repository = InMemoryAssignmentRepository();

    // 第一次：填标题后取消，不应写入任何记录。
    var context = await _host(tester);
    showDialog<bool>(
      context: context,
      builder: (_) => AssignmentEditor(repository: repository, courseId: 'c1'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('assignment-title')), '不该被保存');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(await repository.listForCourse('c1'), isEmpty);

    // 第二次：填标题后保存，应写入一条且字段正确。
    context = await _host(tester);
    showDialog<bool>(
      context: context,
      builder: (_) => AssignmentEditor(repository: repository, courseId: 'c1'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('assignment-title')), '第一章习题');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final rows = await repository.listForCourse('c1');
    expect(rows, hasLength(1));
    expect(rows.single.title, '第一章习题');
    expect(rows.single.courseId, 'c1');
    expect(rows.single.description, isNull);
    expect(rows.single.dueAt.isUtc, isFalse);
  });

  testWidgets('作业编辑器：标题为空时保存被拒绝并保留输入', (tester) async {
    final repository = InMemoryAssignmentRepository();
    final context = await _host(tester);
    showDialog<bool>(
      context: context,
      builder: (_) => AssignmentEditor(repository: repository, courseId: 'c1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('作业标题不能为空'), findsOneWidget);
    expect(await repository.listForCourse('c1'), isEmpty);
  });

  testWidgets('考试编辑器：保存后时间与地点正确写入仓库', (tester) async {
    final repository = InMemoryExamRepository();
    final context = await _host(tester);
    showDialog<bool>(
      context: context,
      builder: (_) => ExamEditor(repository: repository, courseId: 'c1'),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('exam-title')), '期中考试');
    await tester.enterText(find.byKey(const Key('exam-location')), 'A101');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final rows = await repository.listForCourse('c1');
    expect(rows, hasLength(1));
    expect(rows.single.title, '期中考试');
    expect(rows.single.location, 'A101');
    expect(rows.single.range.start.isBefore(rows.single.range.end), isTrue);
  });

  testWidgets('考试编辑器：编辑已有时段是更新而非新增', (tester) async {
    final repository = InMemoryExamRepository();
    final existing = ExamEditor(repository: repository, courseId: 'c1');

    // 先建一条。
    var context = await _host(tester);
    showDialog<bool>(context: context, builder: (_) => existing);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exam-title')), '期中考试');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final created = (await repository.listForCourse('c1')).single;

    // 再以编辑模式打开同一条，改标题后保存。
    context = await _host(tester);
    showDialog<bool>(
      context: context,
      builder: (_) =>
          ExamEditor(repository: repository, courseId: 'c1', exam: created),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exam-title')), '期末考试');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final rows = await repository.listForCourse('c1');
    expect(rows, hasLength(1), reason: '编辑不应产生第二条记录');
    expect(rows.single.id, created.id);
    expect(rows.single.title, '期末考试');
    expect(rows.single.range.start, created.range.start);
  });

  group('展示排序不依赖仓库返回顺序', () {
    test('作业按截止时间升序，且不改动入参', () {
      final rows = [
        Assignment(
          id: 'a3',
          courseId: 'c1',
          title: '晚',
          dueAt: DateTime(2026, 11, 20),
        ),
        Assignment(
          id: 'a1',
          courseId: 'c1',
          title: '早',
          dueAt: DateTime(2026, 11, 10),
        ),
        Assignment(
          id: 'a2',
          courseId: 'c1',
          title: '中',
          dueAt: DateTime(2026, 11, 15),
        ),
      ];
      final sorted = sortAssignmentsForDisplay(rows);
      expect(sorted.map((row) => row.id), ['a1', 'a2', 'a3']);
      expect(rows.map((row) => row.id), ['a3', 'a1', 'a2'], reason: '入参不应被修改');
    });

    test('考试按开始时间升序', () {
      final rows = [
        Exam(
          id: 'e2',
          courseId: 'c1',
          title: '后',
          range: TimeRange(
            start: DateTime(2026, 12, 2, 9),
            end: DateTime(2026, 12, 2, 11),
          ),
        ),
        Exam(
          id: 'e1',
          courseId: 'c1',
          title: '前',
          range: TimeRange(
            start: DateTime(2026, 11, 20, 9),
            end: DateTime(2026, 11, 20, 11),
          ),
        ),
      ];
      expect(sortExamsForDisplay(rows).map((row) => row.id), ['e1', 'e2']);
    });

    test('可接受不可修改列表', () {
      final rows = List<Assignment>.unmodifiable([
        Assignment(
          id: 'a2',
          courseId: 'c1',
          title: '后',
          dueAt: DateTime(2026, 11, 20),
        ),
        Assignment(
          id: 'a1',
          courseId: 'c1',
          title: '前',
          dueAt: DateTime(2026, 11, 10),
        ),
      ]);
      expect(sortAssignmentsForDisplay(rows).map((row) => row.id), [
        'a1',
        'a2',
      ]);
    });
  });
}
