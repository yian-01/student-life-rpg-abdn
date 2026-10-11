import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/models/local_datetime_json.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  group('Task', () {
    final dueAt = DateTime(2026, 10, 5, 23, 30);
    final scheduledRange = TimeRange(
      start: DateTime(2026, 10, 5, 20, 0),
      end: DateTime(2026, 10, 5, 21, 0),
    );

    test('validates fields and keeps dueAt distinct from scheduledRange', () {
      final task = Task(
        id: 'task-1',
        title: 'Read chapter',
        estimatedMinutes: 45,
        dueAt: dueAt,
        scheduledRange: scheduledRange,
      );

      expect(task.dueAt, dueAt);
      expect(task.scheduledRange, scheduledRange);
      expect(task.isCompleted, isFalse);
    });

    test('rejects non-positive duration, empty fields, and UTC values', () {
      expect(
        () => Task(id: '', title: 'Task', estimatedMinutes: 10),
        throwsArgumentError,
      );
      expect(
        () => Task(id: 'task-1', title: ' ', estimatedMinutes: 10),
        throwsArgumentError,
      );
      expect(
        () => Task(id: 'task-1', title: 'Task', estimatedMinutes: 0),
        throwsArgumentError,
      );
      expect(
        () => Task(
          id: 'task-1',
          title: 'Task',
          estimatedMinutes: 10,
          dueAt: DateTime.utc(2026, 10, 5),
        ),
        throwsArgumentError,
      );
    });

    test('copyWith cannot change id and can clear nullable fields', () {
      final task = Task(
        id: 'task-1',
        title: 'Read chapter',
        estimatedMinutes: 45,
        dueAt: dueAt,
        scheduledRange: scheduledRange,
      );

      final cleared = task.copyWith(dueAt: null, scheduledRange: null);
      expect(cleared.id, task.id);
      expect(cleared.dueAt, isNull);
      expect(cleared.scheduledRange, isNull);
    });

    test('JSON round-trip preserves nulls and local civil time', () {
      final task = Task(
        id: 'task-1',
        title: 'Read chapter',
        estimatedMinutes: 45,
        dueAt: dueAt,
        scheduledRange: scheduledRange,
      );

      final restored = Task.fromJson(task.toJson());
      expect(restored, task);
      expect(restored.toJson()['dueAt'], '2026-10-05T23:30:00.000');
    });

    test('JSON writes nullable fields explicitly as null', () {
      final json = Task(
        id: 'task-1',
        title: 'Read chapter',
        estimatedMinutes: 45,
      ).toJson();

      expect(json.keys, contains('dueAt'));
      expect(json['dueAt'], isNull);
      expect(json['scheduledRange'], isNull);
    });

    test('JSON reader rejects Z and offset date-times', () {
      final base = <String, dynamic>{
        'id': 'task-1',
        'title': 'Read chapter',
        'estimatedMinutes': 45,
        'isCompleted': false,
        'scheduledRange': null,
      };

      expect(
        () => Task.fromJson({...base, 'dueAt': '2026-10-05T23:30:00Z'}),
        throwsFormatException,
      );
      expect(
        () => Task.fromJson({...base, 'dueAt': '2026-10-05T23:30:00+08:00'}),
        throwsFormatException,
      );
    });

    test('JSON reader rejects normalized invalid calendar values', () {
      final base = <String, dynamic>{
        'id': 'task-1',
        'title': 'Read chapter',
        'estimatedMinutes': 45,
        'isCompleted': false,
        'scheduledRange': null,
      };

      for (final invalid in [
        '2026-02-29T08:00:00',
        '2026-10-05T24:00:00',
        '2026-10-05T08:60:00',
      ]) {
        expect(
          () => Task.fromJson({...base, 'dueAt': invalid}),
          throwsFormatException,
          reason: invalid,
        );
      }
    });

    test('JSON reader requires isCompleted and rejects non-String keys', () {
      expect(
        () => Task.fromJson({
          'id': 'task-1',
          'title': 'Read chapter',
          'estimatedMinutes': 45,
          'dueAt': null,
          'scheduledRange': null,
        }),
        throwsFormatException,
      );
      expect(
        () => readJsonMap(<Object?, Object?>{1: 'invalid key'}, 'Task'),
        throwsFormatException,
      );
    });

    test('JSON reader rejects unknown fields and invalid domain values', () {
      final valid = <String, dynamic>{
        'id': 'task-1',
        'title': 'Read chapter',
        'estimatedMinutes': 45,
        'isCompleted': false,
        'dueAt': null,
        'scheduledRange': null,
      };

      expect(
        () => Task.fromJson({...valid, 'deadline': '2026-10-05T23:30:00'}),
        throwsFormatException,
      );
      expect(
        () => Task.fromJson({...valid, 'estimatedMinutes': 0}),
        throwsFormatException,
      );
      expect(
        () => Task.fromJson({...valid, 'id': '  '}),
        throwsFormatException,
      );
    });
  });
}
