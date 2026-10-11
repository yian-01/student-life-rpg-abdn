import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/dashboard/models/section_state.dart';
import 'package:student_life_rpg/features/dashboard/presentation/dashboard_layout.dart';
import 'package:student_life_rpg/features/dashboard/presentation/dashboard_section_view.dart';

List<Widget> _sections() => [
  for (var i = 1; i <= 4; i++)
    DashboardSectionView<String>(
      key: Key('s$i'),
      title: '分区$i',
      state: SectionState<String>.ready('数据$i'),
      contentBuilder: (_, data) => Text(data),
    ),
];

Widget _layoutHarness(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: 800,
        child: DashboardSectionLayout(sections: _sections()),
      ),
    ),
  );
}

void main() {
  group('DashboardSectionView 分区状态呈现', () {
    Future<void> pumpSection(
      WidgetTester tester,
      Widget section, {
      double width = 300,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: width, child: section),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('loading 显示加载中', (tester) async {
      await pumpSection(
        tester,
        const DashboardSectionView<String>(
          title: '任务',
          state: SectionState<String>.loading(),
        ),
      );
      expect(find.text('加载中'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('notIntegrated 显示未接入', (tester) async {
      await pumpSection(
        tester,
        const DashboardSectionView<String>(
          title: '任务',
          state: SectionState<String>.notIntegrated(),
        ),
      );
      expect(find.text('未接入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('error 显示失败与重试，重试回调触发', (tester) async {
      var retried = 0;
      await pumpSection(
        tester,
        DashboardSectionView<int>(
          title: 'GPA',
          state: SectionState<int>.failure(StateError('网络故障')),
          onRetry: () => retried++,
        ),
      );
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('网络故障'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(retried, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ready 使用内容构建器；未提供时显示暂无数据', (tester) async {
      await pumpSection(
        tester,
        DashboardSectionView<String>(
          title: '今日活动',
          state: SectionState<String>.ready('3 项活动'),
          contentBuilder: (_, data) => Text(data),
        ),
      );
      expect(find.text('3 项活动'), findsOneWidget);

      await pumpSection(
        tester,
        DashboardSectionView<String>(
          title: '财务',
          state: SectionState<String>.ready('汇总'),
        ),
      );
      expect(find.text('暂无数据'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DashboardSectionLayout 响应式布局（验收：599/600/601/>1200）', () {
    testWidgets('内容宽度 599：单列', (tester) async {
      await tester.pumpWidget(_layoutHarness(tester, 599));
      final r1 = tester.getRect(find.byKey(const Key('s1')));
      final r2 = tester.getRect(find.byKey(const Key('s2')));
      expect(r1.left, r2.left);
      expect(r2.top, greaterThanOrEqualTo(r1.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('内容宽度 600：双列', (tester) async {
      await tester.pumpWidget(_layoutHarness(tester, 600));
      final r1 = tester.getRect(find.byKey(const Key('s1')));
      final r2 = tester.getRect(find.byKey(const Key('s2')));
      expect(r2.left, greaterThan(r1.right));
      expect(r2.top, r1.top);
      expect(tester.takeException(), isNull);
    });

    testWidgets('内容宽度 601：双列', (tester) async {
      await tester.pumpWidget(_layoutHarness(tester, 601));
      final r1 = tester.getRect(find.byKey(const Key('s1')));
      final r2 = tester.getRect(find.byKey(const Key('s2')));
      expect(r2.left, greaterThan(r1.right));
      expect(r2.top, r1.top);
      expect(tester.takeException(), isNull);
    });

    testWidgets('窗口宽于 1200：内容限宽 1200 并居中，仍为双列', (tester) async {
      await tester.pumpWidget(_layoutHarness(tester, 1300));
      final r1 = tester.getRect(find.byKey(const Key('s1')));
      final r2 = tester.getRect(find.byKey(const Key('s2')));
      expect(r1.left, 66); // (1300-1200)/2 + 16 内边距
      expect(r2.left, greaterThan(r1.right));
      expect(r2.top, r1.top);
      expect(tester.takeException(), isNull);
    });

    testWidgets('小窗口长标题与长内容不溢出', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(240, 320);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 320,
              child: DashboardSectionLayout(
                sections: [
                  DashboardSectionView<String>(
                    key: const Key('long-title'),
                    title: '这是一个非常长的分区标题用来验证小窗口下文本能够正常换行而不会产生渲染溢出异常',
                    state: SectionState<String>.ready(
                      '这是一段非常长的分区内容，用来验证在极窄的窗口宽度下文本可以逐行换行展示，'
                      '不会因为固定高度或不可换行的组件而出现黄黑相间的溢出条纹。',
                    ),
                    contentBuilder: (_, data) => Text(data),
                  ),
                  DashboardSectionView<String>(
                    key: const Key('second'),
                    title: '第二个分区',
                    state: SectionState<String>.notIntegrated(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
