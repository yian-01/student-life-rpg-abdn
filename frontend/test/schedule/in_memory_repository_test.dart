import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_event_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/in_memory_task_repository.dart';
import 'package:student_life_rpg/features/schedule/repositories/task_repository.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  group('InMemoryTaskRepository', () {
    test('implements CRUD errors and defensive list copies', () async {
      final repository = InMemoryTaskRepository();
      final task = Task(id: 'task-1', title: 'Task', estimatedMinutes: 10);

      await repository.insert(task);
      expect(await repository.getById('missing'), isNull);
      expect(await repository.remove('missing'), isFalse);
      await expectLater(repository.insert(task), throwsStateError);
      await expectLater(
        repository.update(
          Task(id: 'missing', title: 'Missing', estimatedMinutes: 10),
        ),
        throwsStateError,
      );

      final snapshot = await repository.list();
      expect(() => snapshot.add(task), throwsUnsupportedError);
      expect((await repository.list()).length, 1);

      final updated = task.copyWith(title: 'Updated');
      await repository.update(updated);
      expect(await repository.getById('task-1'), updated);
      expect(await repository.remove('task-1'), isTrue);
      expect(await repository.list(), isEmpty);
    });

    test('stays usable through the TaskRepository contract', () async {
      final TaskRepository repository = InMemoryTaskRepository();
      await repository.insert(
        Task(id: 'task-1', title: 'Task', estimatedMinutes: 10),
      );

      await repository.setCompleted('task-1', true);
      expect((await repository.getById('task-1'))!.isCompleted, isTrue);
    });

    test('completed state is set explicitly and is idempotent', () async {
      final repository = InMemoryTaskRepository();
      await repository.insert(
        Task(id: 'task-1', title: 'Task', estimatedMinutes: 10),
      );

      await repository.setCompleted('task-1', true);
      final afterFirst = await repository.getById('task-1');
      await repository.setCompleted('task-1', true);
      final afterSecond = await repository.getById('task-1');
      expect(afterFirst!.isCompleted, isTrue);
      expect(identical(afterFirst, afterSecond), isTrue);

      await repository.setCompleted('task-1', false);
      expect((await repository.getById('task-1'))!.isCompleted, isFalse);
      await expectLater(
        repository.setCompleted('missing', true),
        throwsStateError,
      );
    });

    test('failed update keeps the original record', () async {
      final repository = InMemoryTaskRepository();
      final original = Task(
        id: 'task-1',
        title: 'Original',
        estimatedMinutes: 10,
      );
      await repository.insert(original);

      await expectLater(
        repository.update(
          Task(id: 'task-2', title: 'Other', estimatedMinutes: 20),
        ),
        throwsStateError,
      );
      expect(await repository.getById('task-1'), original);
      expect(await repository.getById('task-2'), isNull);
    });

    test('rejects blank ids with ArgumentError', () async {
      final repository = InMemoryTaskRepository();

      await expectLater(repository.getById('  '), throwsArgumentError);
      await expectLater(repository.remove(''), throwsArgumentError);
      await expectLater(
        repository.setCompleted(' ', true),
        throwsArgumentError,
      );
    });
  });

  group('InMemoryEventRepository', () {
    test('implements CRUD errors and defensive list copies', () async {
      final repository = InMemoryEventRepository();
      final range = TimeRange(
        start: DateTime(2026, 10, 5, 9),
        end: DateTime(2026, 10, 5, 10),
      );
      final event = Event(id: 'event-1', title: 'Event', range: range);

      await repository.insert(event);
      expect(await repository.getById('missing'), isNull);
      expect(await repository.remove('missing'), isFalse);
      await expectLater(repository.insert(event), throwsStateError);
      await expectLater(
        repository.update(Event(id: 'missing', title: 'Missing', range: range)),
        throwsStateError,
      );

      final snapshot = await repository.list();
      expect(() => snapshot.add(event), throwsUnsupportedError);
      expect((await repository.list()).single, event);
    });
  });
}
