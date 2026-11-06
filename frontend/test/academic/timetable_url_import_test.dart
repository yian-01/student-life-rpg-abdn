import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/academic/presentation/timetable_import_page.dart';
import 'package:student_life_rpg/features/academic/services/timetable_import.dart';
import 'package:student_life_rpg/features/academic/services/timetable_source.dart';

import '../support/campus_fixture.dart';

/// 假的抓取层：按需返回 HTML 或抛出稳定错误码。
class _FakeLoader implements TimetableHtmlLoader {
  _FakeLoader({this.html = '', this.error});

  final String html;
  final TimetableLoadError? error;
  Uri? lastUrl;

  @override
  Future<String> load(
    Uri url, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    lastUrl = url;
    final failure = error;
    if (failure != null) throw TimetableLoadException(failure);
    return html;
  }
}

/// 假的解析层：返回预置结果，并记录收到的 HTML。
class _FakeParser implements TimetableHtmlParser {
  _FakeParser(this.result);
  final TimetableParseResult result;
  String? lastHtml;

  @override
  TimetableParseResult parse(String html, {int? maxWeek}) {
    lastHtml = html;
    return result;
  }
}

TimetableParseResult _oneCourse() => TimetableParseResult(
  courses: [
    ParsedCourse(
      name: '数据结构与算法',
      classCode: '(2026-2027-1)-DLH58271-CS0202',
      credits: 3.5,
      slots: [
        ParsedSlot(
          weekday: 1,
          startMinute: 14 * 60,
          endMinute: 16 * 60 + 20,
          weeks: const [1, 2, 3],
        ),
      ],
    ),
  ],
  issues: const [],
);

Future<void> _openUrlTab(WidgetTester tester) async {
  await tester.tap(find.text('网址导入'));
  await tester.pumpAndSettle();
}

void main() {
  group('parseTimetableUrl', () {
    test('只接受 HTTPS 且不带 userInfo', () {
      expect(
        parseTimetableUrl('https://jwxt.scnu.edu.cn/kbcx/page')?.host,
        'jwxt.scnu.edu.cn',
      );
      expect(parseTimetableUrl('http://jwxt.scnu.edu.cn/kbcx'), isNull);
      expect(parseTimetableUrl('https://user:pass@jwxt.scnu.edu.cn/x'), isNull);
      expect(parseTimetableUrl(''), isNull);
      expect(parseTimetableUrl('随便写的'), isNull);
      expect(parseTimetableUrl('https://'), isNull);
    });
  });

  group('网址导入的界面状态', () {
    testWidgets('默认实现明确提示抓取层未接入，绝不假成功', (tester) async {
      final data = await campusWithCourse();
      addTearDown(data.dispose);
      final semesters = await data.semesters.list();

      await tester.pumpWidget(
        MaterialApp(
          home: TimetableImportPage(data: data, semesters: semesters),
        ),
      );
      await tester.pumpAndSettle();
      await _openUrlTab(tester);

      await tester.enterText(
        find.byKey(const Key('timetable-url')),
        'https://jwxt.example.edu.cn/kbcx',
      );
      await tester.tap(find.byKey(const Key('parse-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('抓取层（#37）尚未接入'), findsOneWidget);
      expect(find.byKey(const Key('import-summary')), findsNothing);
      expect(await data.courses.list(), hasLength(1), reason: '不得写入任何课程');
    });

    for (final entry in <TimetableLoadError, String>{
      TimetableLoadError.loginExpired: '登录已失效',
      TimetableLoadError.networkTimeout: '加载超时',
      TimetableLoadError.unsupportedPage: '不是受支持的课表页面',
      TimetableLoadError.networkUnavailable: '网络不可用',
    }.entries) {
      testWidgets('抓取失败 ${entry.key.name} 时给出可理解提示', (tester) async {
        final data = await campusWithCourse();
        addTearDown(data.dispose);
        final semesters = await data.semesters.list();

        await tester.pumpWidget(
          MaterialApp(
            home: TimetableImportPage(
              data: data,
              semesters: semesters,
              htmlLoader: _FakeLoader(error: entry.key),
              htmlParser: _FakeParser(_oneCourse()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _openUrlTab(tester);
        await tester.enterText(
          find.byKey(const Key('timetable-url')),
          'https://jwxt.example.edu.cn/kbcx',
        );
        await tester.tap(find.byKey(const Key('parse-button')));
        await tester.pumpAndSettle();

        expect(find.textContaining(entry.value), findsOneWidget);
        expect(find.byKey(const Key('import-summary')), findsNothing);
      });
    }

    testWidgets('非法网址不发请求，直接提示', (tester) async {
      final loader = _FakeLoader(html: '<html></html>');
      final data = await campusWithCourse();
      addTearDown(data.dispose);
      final semesters = await data.semesters.list();

      await tester.pumpWidget(
        MaterialApp(
          home: TimetableImportPage(
            data: data,
            semesters: semesters,
            htmlLoader: loader,
            htmlParser: _FakeParser(_oneCourse()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openUrlTab(tester);
      await tester.enterText(
        find.byKey(const Key('timetable-url')),
        'http://insecure.example.edu.cn/kbcx',
      );
      await tester.tap(find.byKey(const Key('parse-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('请输入有效的 HTTPS'), findsOneWidget);
      expect(loader.lastUrl, isNull, reason: '非法网址不应触发抓取');
    });

    testWidgets('抓取成功后进入预览，确认才写入', (tester) async {
      final loader = _FakeLoader(html: '<table id="kbgrid_table_0"></table>');
      final parser = _FakeParser(_oneCourse());
      final data = await campusWithCourse();
      addTearDown(data.dispose);
      final semesters = await data.semesters.list();

      await tester.pumpWidget(
        MaterialApp(
          home: TimetableImportPage(
            data: data,
            semesters: semesters,
            htmlLoader: loader,
            htmlParser: parser,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openUrlTab(tester);
      await tester.enterText(
        find.byKey(const Key('timetable-url')),
        'https://jwxt.example.edu.cn/kbcx',
      );
      await tester.tap(find.byKey(const Key('parse-button')));
      await tester.pumpAndSettle();

      expect(parser.lastHtml, contains('kbgrid_table_0'));
      expect(find.byKey(const Key('import-summary')), findsOneWidget);
      expect(find.textContaining('新增 1 门'), findsOneWidget);

      final before = (await data.courses.list()).length;
      await tester.scrollUntilVisible(
        find.byKey(const Key('confirm-import')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('confirm-import')));
      await tester.pumpAndSettle();

      expect(find.textContaining('已导入'), findsOneWidget);
      expect(await data.courses.list(), hasLength(before + 1));
    });
  });
}
