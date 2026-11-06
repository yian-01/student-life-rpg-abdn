import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/schedule/controllers/day_schedule_controller.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/day_schedule_service.dart';
import 'package:student_life_rpg/features/schedule/services/task_schedule_adapter.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

final day = DateTime(2028, 2, 28); // Monday; next day is a leap day.
TimeRange range(int startHour, int endHour) => TimeRange(
  start: DateTime(2028, 2, 28, startHour),
  end: DateTime(2028, 2, 28, endHour),
);
Exam exam(String id, TimeRange times) =>
    Exam(id: id, courseId: 'course', title: '考试$id', range: times);
Assignment assignment(String id, DateTime dueAt) =>
    Assignment(id: id, courseId: 'course', title: '作业$id', dueAt: dueAt);

void main() {
  late Directory directory;
  late CampusData data;
  late FileTaskRepository tasks;
  CampusData openCampus() => CampusData(
    CampusStore(const FileJsonDocumentStore(), '${directory.path}/campus.json'),
  );
  FileTaskRepository openTasks() => FileTaskRepository(
    const FileJsonDocumentStore(),
    '${directory.path}/tasks.json',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('schedule-real-');
    data = openCampus();
    tasks = openTasks();
    await data.semesters.insert(
      Semester(
        id: 'term',
        name: '学期',
        startDate: day,
        endDate: DateTime(2028, 12, 31),
        week1Monday: day,
      ),
    );
    await data.courses.insert(
      Course(
        id: 'course',
        semesterId: 'term',
        name: '课程',
        credits: 3,
        scoreScaleMax: 4,
        slots: [
          CourseSlot(weekday: 1, startMinute: 540, endMinute: 600, weeks: [1]),
          CourseSlot(weekday: 1, startMinute: 660, endMinute: 720, weeks: [1]),
        ],
      ),
    );
  });
  tearDown(() async {
    data.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'SC01/SC02/SC07 real repositories: exams move/delete, deadlines stay separate, reopen has no duplicates',
    () async {
      await data.events.insert(
        Event(id: 'meeting', title: '事件', range: range(9, 10)),
      );
      await tasks.insert(
        Task(
          id: 'task',
          title: '任务',
          estimatedMinutes: 60,
          scheduledRange: range(9, 10),
        ),
      );
      await data.exams.insert(exam('考试:<1>', range(9, 10)));
      await data.assignments.insert(assignment('a', DateTime(2028, 2, 28, 10)));
      var result = await data.schedule(tasks).loadDay(day);
      expect(result.errors, isEmpty);
      expect(result.items.map((item) => item.sourceType), [
        ScheduleSourceType.course,
        ScheduleSourceType.event,
        ScheduleSourceType.task,
        ScheduleSourceType.exam,
        ScheduleSourceType.course,
      ]);
      final original = result.items.singleWhere(
        (item) => item.sourceType == ScheduleSourceType.exam,
      );
      expect(original.sourceId, '考试:<1>');
      expect(original.id, startsWith('exam:${Uri.encodeComponent('考试:<1>')}:'));
      expect(result.assignmentDeadlines.single.id, 'a');
      expect(
        await tasks.list(),
        hasLength(1),
        reason: 'Assignment must not become a Task',
      );
      expect(result.items.any((item) => item.sourceId == 'a'), isFalse);
      final next = TimeRange(
        start: DateTime(2028, 2, 29, 9),
        end: DateTime(2028, 2, 29, 10),
      );
      await data.exams.update(exam('考试:<1>', next));
      await data.assignments.update(
        assignment('a', DateTime(2028, 2, 29, 23, 59)),
      );
      result = await data.schedule(tasks).loadDay(day);
      expect(
        result.items.where(
          (item) => item.sourceType == ScheduleSourceType.exam,
        ),
        isEmpty,
      );
      expect(result.assignmentDeadlines, isEmpty);
      final cold = openCampus();
      final coldTasks = openTasks();
      addTearDown(cold.dispose);
      result = await cold.schedule(coldTasks).loadDay(DateTime(2028, 2, 29));
      expect(result.items.single.range.start, next.start);
      expect(result.items.single.sourceId, original.sourceId);
      expect(
        result.assignmentDeadlines.single.dueAt,
        DateTime(2028, 2, 29, 23, 59),
      );
      await cold.exams.remove(original.sourceId);
      await cold.assignments.remove('a');
      final reopened = openCampus();
      addTearDown(reopened.dispose);
      result = await reopened
          .schedule(openTasks())
          .loadDay(DateTime(2028, 2, 29));
      expect(result.items, isEmpty);
      expect(result.assignmentDeadlines, isEmpty);
    },
  );

  test(
    'SC03 each timed source spans both days; midnight ends are excluded',
    () async {
      for (final endMinute in [0, 10]) {
        final times = TimeRange(
          start: DateTime(2028, 2, 28, 23, 30),
          end: DateTime(2028, 2, 29, 0, endMinute),
        );
        await data.events.insert(
          Event(id: 'e$endMinute', title: '事件', range: times),
        );
        await tasks.insert(
          Task(
            id: 't$endMinute',
            title: '任务',
            estimatedMinutes: 30,
            scheduledRange: times,
          ),
        );
        await data.exams.insert(exam('x$endMinute', times));
      }
      final first = await data.schedule(tasks).loadDay(day);
      final second = await data.schedule(tasks).loadDay(DateTime(2028, 2, 29));
      expect(
        first.items.where(
          (item) => item.sourceType != ScheduleSourceType.course,
        ),
        hasLength(6),
      );
      expect(second.items, hasLength(3));
      expect(
        second.items.every((item) => item.sourceId.endsWith('10')),
        isTrue,
      );
      for (final item in second.items) {
        expect(item.range.start, DateTime(2028, 2, 28, 23, 30));
        expect(
          first.items.singleWhere((row) => row.id == item.id).range,
          isNotNull,
        );
        expect(second.isCrossDay(item), isTrue);
      }
    },
  );

  test(
    'SC04/SC05 all timed-source conflict pairs, exam/exam and completed task exclusion',
    () async {
      await tasks.insert(
        Task(
          id: 'task',
          title: '同名',
          estimatedMinutes: 60,
          scheduledRange: range(9, 10),
        ),
      );
      await data.events.insert(
        Event(id: 'event', title: '同名', range: range(9, 10)),
      );
      await data.exams.insert(exam('x1', range(9, 10)));
      await data.exams.insert(exam('x2', range(9, 10)));
      await data.assignments.insert(
        assignment('a', DateTime(2028, 2, 28, 9, 30)),
      );
      final controller = DayScheduleController(
        loader: data.schedule(tasks),
        taskRepository: tasks,
        initialDate: day,
      );
      addTearDown(controller.dispose);
      await controller.loadDay();
      expect(
        controller.conflicts,
        hasLength(10),
        reason: '5 overlapping items form 10 pairs; deadline excluded',
      );
      await controller.setTaskCompleted('task', true);
      expect(controller.conflicts, hasLength(6));
      expect(
        controller.schedule!.items.any((item) => item.sourceId == 'task'),
        isTrue,
      );
      await data.exams.update(exam('x2', range(10, 11)));
      await controller.retry();
      expect(
        controller.conflicts,
        hasLength(3),
        reason: 'Boundary contact is not overlap',
      );
      await data.exams.update(
        exam(
          'x2',
          TimeRange(
            start: DateTime(2028, 2, 28, 9, 59),
            end: DateTime(2028, 2, 28, 11),
          ),
        ),
      );
      await controller.retry();
      expect(controller.conflicts, hasLength(6));
    },
  );

  test(
    'SC06 stable ordering and IDs across refreshes and new repository instances',
    () async {
      for (final id in ['z', 'a', 'same:<id>']) {
        await data.exams.insert(exam(id, range(9, 10)));
      }
      final expected = (await data.schedule(tasks).loadDay(day)).items
          .map((item) => item.id)
          .toList();
      for (var i = 0; i < 3; i++) {
        final cold = openCampus();
        expect(
          (await cold.schedule(openTasks()).loadDay(day)).items.map(
            (item) => item.id,
          ),
          expected,
        );
        cold.dispose();
      }
      expect(expected.toSet(), hasLength(expected.length));
      expect(
        TaskScheduleAdapter.buildItemId(
          ScheduleSourceType.exam,
          'x',
          DateTime(2028, 2, 28, 9, 0, 0, 1, 1),
        ),
        isNot(
          TaskScheduleAdapter.buildItemId(
            ScheduleSourceType.exam,
            'x',
            DateTime(2028, 2, 28, 9, 0, 0, 1, 2),
          ),
        ),
      );
    },
  );

  for (final bad in ['Task', 'Campus', 'Both']) {
    test(
      'SC10 $bad corruption preserves healthy sources and explicit recovery reloads selected day',
      () async {
        await tasks.insert(Task(id: 't1', title: '任务1', estimatedMinutes: 30));
        await tasks.insert(Task(id: 't2', title: '任务2', estimatedMinutes: 30));
        await data.exams.insert(exam('x', range(9, 10)));
        await data.assignments.insert(
          assignment('a', DateTime(2028, 2, 28, 18)),
        );
        if (bad != 'Campus') {
          await File('${directory.path}/tasks.json').writeAsString('{bad');
        }
        if (bad != 'Task') {
          await File('${directory.path}/campus.json').writeAsString('{bad');
        }
        final cold = openCampus();
        final coldTasks = openTasks();
        addTearDown(cold.dispose);
        final controller = DayScheduleController(
          loader: cold.schedule(coldTasks),
          taskRepository: coldTasks,
          initialDate: day,
        );
        addTearDown(controller.dispose);
        await controller.loadDay();
        expect(
          controller.schedule!.errors.containsKey(ScheduleDataSource.tasks),
          bad != 'Campus',
        );
        expect(
          controller.schedule!.errors.containsKey(ScheduleDataSource.exams),
          bad != 'Task',
        );
        if (bad == 'Task') {
          expect(
            controller.schedule!.items.where(
              (item) => item.sourceType == ScheduleSourceType.exam,
            ),
            hasLength(1),
          );
        }
        if (bad == 'Campus') {
          expect(controller.schedule!.unscheduledTasks, hasLength(2));
        }
        if (bad != 'Campus') await coldTasks.recoverFromBackup();
        if (bad != 'Task') await cold.store.recoverFromBackup();
        await controller.retry();
        expect(controller.selectedDate, day);
        expect(controller.schedule!.errors, isEmpty);
        expect(
          controller.schedule!.unscheduledTasks,
          hasLength(bad == 'Campus' ? 2 : 1),
        );
        expect(
          controller.schedule!.items.where(
            (item) => item.sourceType == ScheduleSourceType.exam,
          ),
          hasLength(1),
        );
      },
    );
  }

  test(
    'SC10 failed recovery retains last successful same-day lists and original exception',
    () async {
      await tasks.insert(Task(id: 't', title: '保留任务', estimatedMinutes: 30));
      final controller = DayScheduleController(
        loader: data.schedule(tasks),
        taskRepository: tasks,
        initialDate: day,
      );
      addTearDown(controller.dispose);
      await controller.loadDay();
      final prior = controller.schedule!;
      final failure = StateError('read failure');
      final partial = DaySchedule(
        date: day,
        items: [],
        unscheduledTasks: [],
        completedTaskIds: {},
        errors: {ScheduleDataSource.tasks: failure},
      );
      final retained = partial.retainingFailedSources(prior);
      expect(retained.unscheduledTasks.single.id, 't');
      expect(retained.errors[ScheduleDataSource.tasks], same(failure));
      await File('${directory.path}/tasks.json').writeAsString('{bad');
      await expectLater(tasks.recoverFromBackup(), throwsFormatException);
      expect((await tasks.list()).single.id, 't');
      expect(await File('${directory.path}/tasks.json').readAsString(), '{bad');
      expect(
        () => retained.assignmentDeadlines.clear(),
        throwsUnsupportedError,
      );
      expect(() => retained.errors.clear(), throwsUnsupportedError);
    },
  );

  test(
    'SC14 real-file CRUD across all sources agrees after reopening both stores',
    () async {
      await data.events.insert(
        Event(id: 'event', title: '原事件', range: range(9, 10)),
      );
      await tasks.insert(
        Task(
          id: 'task',
          title: '原任务',
          estimatedMinutes: 30,
          scheduledRange: range(9, 10),
          dueAt: DateTime(2028, 3, 1, 18),
        ),
      );
      await data.exams.insert(exam('exam', range(9, 10)));
      await data.assignments.insert(
        assignment('assignment', DateTime(2028, 2, 28, 18)),
      );
      final nextRange = TimeRange(
        start: DateTime(2028, 2, 29, 9),
        end: DateTime(2028, 2, 29, 10),
      );
      final oldCourse = (await data.courses.getById('course'))!;
      await data.courses.update(
        Course(
          id: oldCourse.id,
          semesterId: oldCourse.semesterId,
          name: '修改课程',
          credits: oldCourse.credits,
          scoreScaleMax: 4,
          slots: [
            CourseSlot(
              weekday: 2,
              startMinute: 540,
              endMinute: 600,
              weeks: [1],
            ),
          ],
        ),
      );
      await data.events.update(
        Event(id: 'event', title: '修改事件', range: nextRange),
      );
      await tasks.update(
        (await tasks.getById(
          'task',
        ))!.copyWith(title: '修改任务', scheduledRange: nextRange),
      );
      await data.exams.update(exam('exam', nextRange));
      await data.assignments.update(
        assignment('assignment', DateTime(2028, 2, 29, 18)),
      );
      final cold = openCampus();
      final coldTasks = openTasks();
      addTearDown(cold.dispose);
      final previous = await cold.schedule(coldTasks).loadDay(day);
      expect(previous.items, isEmpty);
      expect(previous.assignmentDeadlines, isEmpty);
      final moved = await cold
          .schedule(coldTasks)
          .loadDay(DateTime(2028, 2, 29));
      expect(
        moved.items.map((item) => item.sourceType).toSet(),
        ScheduleSourceType.values.toSet(),
      );
      expect(moved.assignmentDeadlines.single.id, 'assignment');
      expect(
        (await coldTasks.getById('task'))!.dueAt,
        DateTime(2028, 3, 1, 18),
      );
      await cold.assignments.remove('assignment');
      await cold.exams.remove('exam');
      await cold.events.remove('event');
      await coldTasks.remove('task');
      await cold.courses.remove('course');
      final reopened = openCampus();
      addTearDown(reopened.dispose);
      final empty = await reopened
          .schedule(openTasks())
          .loadDay(DateTime(2028, 2, 29));
      expect(empty.items, isEmpty);
      expect(empty.assignmentDeadlines, isEmpty);
      expect(empty.unscheduledTasks, isEmpty);
      expect(empty.errors, isEmpty);
    },
  );
}
