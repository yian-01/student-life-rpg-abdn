import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/presentation/timetable_import_page.dart';

import '../support/campus_fixture.dart';

const _timetableText = '''
星期一
5-7
数据结构与算法* 周数：1-16周 校区:南海 上课地点：教C402 教师 ：周国靖 教学班：(2026-2027-1)-DLH58271-CS0202 教学班组成：25软件工程2班 考核方式：考试 选课备注：  课程学时组成：理论:48 周学时：3 总学时：48 学分：3.5
8-8
数据结构与算法& 周数：1-16周 校区:南海 上课地点：教C402 教师 ：周国靖 教学班：(2026-2027-1)-DLH58271-CS0202A 教学班组成：25软件工程2班 考核方式：未安排 选课备注：  课程学时组成：理论:48,实验:16 周学时：1 总学时：16 学分：3.5
''';

void main() {
  testWidgets('解析后显示预览，确认导入写入课程', (tester) async {
    final data = await campusWithCourse();
    addTearDown(data.dispose);
    final semesters = await data.semesters.list();

    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(data: data, semesters: semesters),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('timetable-input')),
      _timetableText,
    );
    await tester.tap(find.byKey(const Key('parse-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('import-summary')), findsOneWidget);
    expect(
      find.textContaining('新增 1 门'),
      findsOneWidget,
      reason: '理论课与实验课应合并为一门',
    );
    expect(find.text('数据结构与算法'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('confirm-import')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-import')));
    await tester.pumpAndSettle();

    final courses = await data.courses.list();
    final imported = courses.where((course) => course.name == '数据结构与算法');
    expect(imported, hasLength(1), reason: '理论课与实验课合并为一门课程');
    expect(imported.single.slots, hasLength(2), reason: '5-7 节与 8-8 节两个时段');
    expect(imported.single.credits, 3.5);
    expect(imported.single.gradePoint, isNull, reason: '导入的课程未评分');
    expect(
      courses.where((course) => course.name == '线性代数'),
      hasLength(1),
      reason: '夹具里原有课程应保留',
    );
  });

  testWidgets('缺失学分补填后可勾选并确认导入', (tester) async {
    final data = await campusWithCourse();
    addTearDown(data.dispose);
    final semesters = await data.semesters.list();
    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(data: data, semesters: semesters),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('timetable-input')),
      _timetableText.replaceAll('学分：3.5', '学分：'),
    );
    await tester.tap(find.byKey(const Key('parse-button')));
    await tester.pumpAndSettle();

    final credits = find.widgetWithText(TextField, '学分（可修正）');
    await tester.ensureVisible(credits);
    await tester.enterText(credits, '2.5');
    await tester.pumpAndSettle();
    final checkbox = find.byType(Checkbox);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirm-import'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    final courses = await data.courses.list();
    final imported = courses.singleWhere((course) => course.name == '数据结构与算法');
    expect(imported.credits, 2.5);
  });

  testWidgets('未点确认时不会写入任何课程', (tester) async {
    final data = await campusWithCourse();
    addTearDown(data.dispose);
    final semesters = await data.semesters.list();
    final before = (await data.courses.list()).length;

    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(data: data, semesters: semesters),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('timetable-input')),
      _timetableText,
    );
    await tester.tap(find.byKey(const Key('parse-button')));
    await tester.pumpAndSettle();

    expect(await data.courses.list(), hasLength(before));
  });

  testWidgets('空文本解析给出明确提示', (tester) async {
    final data = await campusWithCourse();
    addTearDown(data.dispose);
    final semesters = await data.semesters.list();

    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(data: data, semesters: semesters),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('parse-button')));
    await tester.pumpAndSettle();

    expect(find.text('请先粘贴课表文本。'), findsOneWidget);
  });

  testWidgets('整批写入失败时不留下半份数据，可修正后重试', (tester) async {
    final documents = MemoryCampusDocuments();
    final data = CampusData(CampusStore(documents, 'campus.json'));
    addTearDown(data.dispose);
    await data.semesters.insert(
      Semester(
        id: 's1',
        name: '测试学期',
        startDate: DateTime(2026, 10, 26),
        endDate: DateTime(2026, 11, 29),
        week1Monday: DateTime(2026, 10, 26),
      ),
    );
    final semesters = await data.semesters.list();

    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(data: data, semesters: semesters),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('timetable-input')),
      _timetableText,
    );
    await tester.tap(find.byKey(const Key('parse-button')));
    await tester.pumpAndSettle();

    // 注入写入失败：整批应回滚，不留半份数据。
    documents.failWrites = true;
    await tester.scrollUntilVisible(
      find.byKey(const Key('confirm-import')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('confirm-import')));
    await tester.pumpAndSettle();

    expect(find.textContaining('未写入任何课程'), findsOneWidget);
    expect(await data.courses.list(), isEmpty, reason: '失败不得半导入');

    // 恢复后可直接重试，预览仍在。
    documents.failWrites = false;
    await tester.scrollUntilVisible(
      find.byKey(const Key('confirm-import')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('confirm-import')));
    await tester.pumpAndSettle();

    expect(find.textContaining('已导入'), findsOneWidget);
    expect(await data.courses.list(), isNotEmpty);
  });

  testWidgets('重复导入同一份课表时明确提示无需导入', (tester) async {
    final data = await campusWithCourse();
    addTearDown(data.dispose);
    final semesters = await data.semesters.list();

    Future<void> openAndParse() async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimetableImportPage(data: data, semesters: semesters),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('timetable-input')),
        _timetableText,
      );
      await tester.tap(find.byKey(const Key('parse-button')));
      await tester.pumpAndSettle();
    }

    // 第一次：正常导入。
    await openAndParse();
    await tester.scrollUntilVisible(
      find.byKey(const Key('confirm-import')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('confirm-import')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已导入'), findsOneWidget);

    // 第二次：同一份内容，应提示无需导入而不是给出可点按钮。
    await openAndParse();
    await tester.scrollUntilVisible(
      find.byKey(const Key('confirm-import')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('无需导入'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-import')),
    );
    expect(button.onPressed, isNull, reason: '没有变更时按钮必须禁用');

    await tester.scrollUntilVisible(
      find.byKey(const Key('nothing-to-import')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nothing-to-import')), findsOneWidget);
    expect(find.textContaining('没有需要写入的课程'), findsOneWidget);

    // 数据不能因为重复导入而变化。
    final courses = await data.courses.list();
    expect(courses.where((course) => course.name == '数据结构与算法'), hasLength(1));
  });
}
