import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/dashboard/models/task_metrics.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

TaskMetricInput _task({
  required String id,
  bool isCompleted = false,
  TimeRange? scheduledRange,
  DateTime? dueAt,
}) => (
  id: id,
  isCompleted: isCompleted,
  scheduledRange: scheduledRange,
  dueAt: dueAt,
);

TimeRange _range(String start, String end) =>
    TimeRange(start: DateTime.parse(start), end: DateTime.parse(end));

void main() {
  // 当天：2026-10-11 本地。
  final today = DateTime(2026, 10, 11, 10, 30);

  group('完成率（验收：总数0/null、0完成、全完成）', () {
    test('总数为 0：completionRate 为 null', () {
      final metrics = computeTaskMetrics(tasks: const [], today: today);
      expect(metrics.totalCount, 0);
      expect(metrics.completedCount, 0);
      expect(metrics.todayPendingCount, 0);
      expect(metrics.completionRate, isNull);
    });

    test('4 项 0 完成：完成率 0', () {
      final metrics = computeTaskMetrics(
        tasks: [
          _task(id: 'a'),
          _task(id: 'b'),
          _task(id: 'c'),
          _task(id: 'd'),
        ],
        today: today,
      );
      expect(metrics.totalCount, 4);
      expect(metrics.completedCount, 0);
      expect(metrics.completionRate, 0.0);
    });

    test('4 项全完成：完成率 1', () {
      final metrics = computeTaskMetrics(
        tasks: [
          _task(id: 'a', isCompleted: true),
          _task(id: 'b', isCompleted: true),
          _task(id: 'c', isCompleted: true),
          _task(id: 'd', isCompleted: true),
        ],
        today: today,
      );
      expect(metrics.completionRate, 1.0);
    });

    test('4 项完成 2 项：完成率 0.5', () {
      final metrics = computeTaskMetrics(
        tasks: [
          _task(id: 'a', isCompleted: true),
          _task(id: 'b'),
          _task(id: 'c', isCompleted: true),
          _task(id: 'd'),
        ],
        today: today,
      );
      expect(metrics.completionRate, 0.5);
    });
  });

  group('今日待办（验收：截止/安排/跨日/双条件去重）', () {
    test('仅当天截止：计入', () {
      final metrics = computeTaskMetrics(
        tasks: [_task(id: 'a', dueAt: DateTime(2026, 10, 11, 15))],
        today: today,
      );
      expect(metrics.todayPendingCount, 1);
    });

    test('仅当天安排：计入', () {
      final metrics = computeTaskMetrics(
        tasks: [
          _task(
            id: 'a',
            scheduledRange: _range(
              '2026-10-11T10:00:00',
              '2026-10-11T11:00:00',
            ),
          ),
        ],
        today: today,
      );
      expect(metrics.todayPendingCount, 1);
    });

    test('跨日安排与当天相交：计入', () {
      final metrics = computeTaskMetrics(
        tasks: [
          _task(
            id: 'a',
            scheduledRange: _range(
              '2026-10-10T22:00:00',
              '2026-10-11T02:00:00',
            ),
          ),
        ],
        today: today,
      );
      expect(metrics.todayPendingCount, 1);
    });

    test('双条件同时满足：按 id 去重只计一次', () {
      final metrics = computeTaskMetrics(
        tasks: [
          _task(
            id: 'a',
            scheduledRange: _range(
              '2026-10-11T09:00:00',
              '2026-10-11T10:00:00',
            ),
            dueAt: DateTime(2026, 10, 11, 18),
          ),
        ],
        today: today,
      );
      expect(metrics.todayPendingCount, 1);
    });

    test('无安排且无当天截止：不计入', () {
      final metrics = computeTaskMetrics(
        tasks: [
          _task(id: 'a'),
          _task(id: 'b', dueAt: DateTime(2026, 10, 12, 9)),
          _task(
            id: 'c',
            scheduledRange: _range(
              '2026-10-12T10:00:00',
              '2026-10-12T11:00:00',
            ),
          ),
        ],
        today: today,
      );
      expect(metrics.todayPendingCount, 0);
    });

    test('已完成任务不计入今日待办', () {
      final metrics = computeTaskMetrics(
        tasks: [
          _task(id: 'a', isCompleted: true, dueAt: DateTime(2026, 10, 11, 9)),
        ],
        today: today,
      );
      expect(metrics.todayPendingCount, 0);
      expect(metrics.completedCount, 1);
    });

    test('半开区间边界：首尾相接不算相交', () {
      final metrics = computeTaskMetrics(
        tasks: [
          // 昨天的安排，end 恰为当天开始：不计。
          _task(
            id: 'a',
            scheduledRange: _range(
              '2026-10-10T20:00:00',
              '2026-10-11T00:00:00',
            ),
          ),
          // 截止恰为当天开始 00:00：计入。
          _task(id: 'b', dueAt: DateTime(2026, 10, 11, 0)),
          // 截止恰为次日 00:00（半开区间终点）：不计。
          _task(id: 'c', dueAt: DateTime(2026, 10, 12, 0)),
        ],
        today: today,
      );
      expect(metrics.todayPendingCount, 1);
    });

    test('重复 id 的输入按 id 去重', () {
      final metrics = computeTaskMetrics(
        tasks: [
          _task(id: 'a', dueAt: DateTime(2026, 10, 11, 9)),
          _task(id: 'a', dueAt: DateTime(2026, 10, 11, 10)),
        ],
        today: today,
      );
      expect(metrics.todayPendingCount, 1);
    });

    test('UTC 时间输入拒绝', () {
      expect(
        () => computeTaskMetrics(
          tasks: [_task(id: 'a', dueAt: DateTime.utc(2026, 10, 11, 9))],
          today: today,
        ),
        throwsArgumentError,
      );
      expect(
        () => computeTaskMetrics(
          tasks: const [],
          today: DateTime.utc(2026, 10, 11),
        ),
        throwsArgumentError,
      );
    });
  });

  group('TaskMetrics 构造校验（契约第 3 节 ArgumentError）', () {
    test('completedCount 超过 totalCount 拒绝', () {
      expect(
        () => TaskMetrics(
          totalCount: 2,
          completedCount: 3,
          todayPendingCount: 0,
          completionRate: 1.5,
        ),
        throwsArgumentError,
      );
    });

    test('总数为 0 但完成率非 null 拒绝', () {
      expect(
        () => TaskMetrics(
          totalCount: 0,
          completedCount: 0,
          todayPendingCount: 0,
          completionRate: 0,
        ),
        throwsArgumentError,
      );
    });

    test('总数大于 0 但完成率为 null 拒绝', () {
      expect(
        () => TaskMetrics(
          totalCount: 3,
          completedCount: 1,
          todayPendingCount: 0,
          completionRate: null,
        ),
        throwsArgumentError,
      );
    });

    test('完成率与完成数不一致拒绝', () {
      expect(
        () => TaskMetrics(
          totalCount: 4,
          completedCount: 2,
          todayPendingCount: 0,
          completionRate: 0.9,
        ),
        throwsArgumentError,
      );
    });

    test('负数输入拒绝', () {
      expect(
        () => TaskMetrics(
          totalCount: -1,
          completedCount: 0,
          todayPendingCount: 0,
          completionRate: null,
        ),
        throwsArgumentError,
      );
    });
  });
}
