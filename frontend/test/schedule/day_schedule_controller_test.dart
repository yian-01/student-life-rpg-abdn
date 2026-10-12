import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';

void main() {
  group('DayScheduleController', () {
    test('loads, navigates, and exposes loading state', () async {
      final loader = _FakeLoader((date) async => _emptySchedule(date));
      final controller = DayScheduleController(
        loader: loader,
        initialDate: DateTime(2026, 10, 5, 9),
      );

      expect(controller.selectedDate, DateTime(2026, 10, 5));
      final future = controller.loadDay();
      expect(controller.isLoading, isTrue);
      await future;
      expect(controller.isLoading, isFalse);
      expect(controller.schedule, isNotNull);

      await controller.goToNextDay();
      expect(controller.selectedDate, DateTime(2026, 10, 6));
      await controller.goToPreviousDay();
      expect(controller.selectedDate, DateTime(2026, 10, 5));
      controller.dispose();
    });

    test('shows an error and can retry', () async {
      var shouldFail = true;
      final loader = _FakeLoader((date) async {
        if (shouldFail) {
          shouldFail = false;
          throw StateError('offline');
        }
        return _emptySchedule(date);
      });
      final controller = DayScheduleController(
        loader: loader,
        initialDate: DateTime(2026, 10, 5),
      );

      await controller.loadDay();
      expect(controller.errorMessage, isNotNull);
      expect(controller.schedule, isNull);

      await controller.retry();
      expect(controller.errorMessage, isNull);
      expect(controller.schedule, isNotNull);
      controller.dispose();
    });

    test('date change clears the previous schedule while loading', () async {
      final completer = Completer<DaySchedule>();
      var requestCount = 0;
      final loader = _FakeLoader((date) {
        requestCount += 1;
        if (requestCount == 1) {
          return Future.value(_emptySchedule(date));
        }
        return completer.future;
      });
      final controller = DayScheduleController(
        loader: loader,
        initialDate: DateTime(2026, 10, 5),
      );

      await controller.loadDay();
      expect(controller.schedule, isNotNull);

      final pending = controller.goToNextDay();
      expect(controller.schedule, isNull);
      expect(controller.isLoading, isTrue);
      completer.complete(_emptySchedule(DateTime(2026, 10, 6)));
      await pending;

      expect(controller.schedule!.date, DateTime(2026, 10, 6));
      controller.dispose();
    });

    test('ignores a stale response after a newer request completes', () async {
      final firstRequest = Completer<DaySchedule>();
      final secondRequest = Completer<DaySchedule>();
      var requestCount = 0;
      final loader = _FakeLoader((date) {
        requestCount += 1;
        return requestCount == 1 ? firstRequest.future : secondRequest.future;
      });
      final controller = DayScheduleController(
        loader: loader,
        initialDate: DateTime(2026, 10, 5),
      );

      final firstLoad = controller.loadDay(DateTime(2026, 10, 5));
      final secondLoad = controller.loadDay(DateTime(2026, 10, 6));
      secondRequest.complete(_emptySchedule(DateTime(2026, 10, 6)));
      await secondLoad;

      expect(controller.schedule!.date, DateTime(2026, 10, 6));
      expect(controller.selectedDate, DateTime(2026, 10, 6));
      expect(controller.isLoading, isFalse);

      firstRequest.complete(_emptySchedule(DateTime(2026, 10, 5)));
      await firstLoad;

      expect(controller.schedule!.date, DateTime(2026, 10, 6));
      expect(controller.selectedDate, DateTime(2026, 10, 6));
      controller.dispose();
    });

    test('rejects UTC dates', () {
      expect(
        () => DayScheduleController(
          loader: _FakeLoader((date) async => _emptySchedule(date)),
          initialDate: DateTime.utc(2026, 10, 5),
        ),
        throwsArgumentError,
      );
    });

    test('does not notify after dispose', () async {
      final controller = DayScheduleController(
        loader: _FakeLoader((date) async => _emptySchedule(date)),
        initialDate: DateTime(2026, 10, 5),
      );
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.dispose();
      await controller.loadDay(DateTime(2026, 10, 6));
      expect(notifications, 0);
    });
  });
}

class _FakeLoader implements DayScheduleLoader {
  _FakeLoader(this._load);

  final Future<DaySchedule> Function(DateTime date) _load;

  @override
  Future<DaySchedule> loadDay(DateTime date) => _load(date);
}

DaySchedule _emptySchedule(DateTime date) {
  return DaySchedule(
    date: date,
    items: const [],
    unscheduledTasks: const [],
    completedTaskIds: const {},
  );
}
