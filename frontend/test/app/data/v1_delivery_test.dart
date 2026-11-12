import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/app/data/full_backup.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_adjustment.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/local_records/local_records_page.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/features/schedule/services/copy_schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Ee0AAAAASUVORK5CYII=';

class _FailTaskReplaceOnce extends DocumentFileOperations {
  bool armed = false;

  @override
  Future<void> rename(File file, String destination) async {
    if (armed &&
        destination.endsWith('/tasks.json') &&
        file.path.endsWith('/tasks.json.tmp')) {
      armed = false;
      throw FileSystemException('Injected task replacement error', file.path);
    }
    await super.rename(file, destination);
  }
}

void main() {
  final monday = DateTime(2026, 11, 2);

  test(
    'pending filters use calendar boundaries and keep task due and schedule independent',
    () {
      final now = DateTime(2026, 11, 2, 12);
      final task = Task(
        id: 'task',
        title: '复习',
        estimatedMinutes: 30,
        dueAt: DateTime(2026, 11, 1),
        scheduledRange: TimeRange(
          start: DateTime(2026, 11, 2, 10),
          end: DateTime(2026, 11, 2, 11),
        ),
      );
      final assignment = Assignment(
        id: 'a',
        courseId: 'c',
        title: '作业',
        dueAt: DateTime(2026, 11, 9),
        status: AssignmentStatus.inProgress,
      );
      expect(matchesTodoPeriod(task, TodoPeriod.today, now), isTrue);
      expect(matchesTodoPeriod(task, TodoPeriod.overdue, now), isTrue);
      expect(
        matchesTodoPeriod(
          task.copyWith(isCompleted: true),
          TodoPeriod.all,
          now,
        ),
        isFalse,
      );
      expect(matchesTodoPeriod(assignment, TodoPeriod.week, now), isFalse);
      expect(
        matchesTodoPeriod(
          Assignment.fromJson({
            ...assignment.toJson(),
            'status': 'submitted',
            'dueAt': DateTime(2026, 11, 1).toIso8601String(),
          }),
          TodoPeriod.overdue,
          now,
        ),
        isFalse,
      );
    },
  );

  test(
    'copy draft preserves duration and deadline and resets completed steps',
    () {
      final original = Task(
        id: 'original',
        title: '值班',
        estimatedMinutes: 60,
        dueAt: DateTime(2026, 11, 3, 12),
        scheduledRange: TimeRange(
          start: DateTime(2026, 11, 2, 23, 30),
          end: DateTime(2026, 11, 3, 0, 30),
        ),
        isCompleted: true,
        priority: TaskPriority.high,
        steps: [TaskStep(id: 'step', title: '检查', done: true)],
      );
      final copy = taskCopyDraft(original, DateTime(2026, 11, 8));
      expect(copy.scheduledRange!.end, DateTime(2026, 11, 9, 0, 30));
      expect(copy.dueAt, original.dueAt);
      expect(copy.priority, TaskPriority.high);
      expect(copy.isCompleted || copy.steps.single.done, isFalse);
      expect(original.isCompleted && original.steps.single.done, isTrue);
    },
  );

  test(
    'course adjustment, status, priority and receipt survive whole-file restore',
    () async {
      final folder = await Directory.systemTemp.createTemp('v1-full-backup');
      addTearDown(() => folder.delete(recursive: true));
      const files = FileJsonDocumentStore();
      final campusPath = '${folder.path}/campus.json';
      final taskPath = '${folder.path}/tasks.json';
      final data = CampusData(CampusStore(files, campusPath));
      addTearDown(data.dispose);
      final tasks = FileTaskRepository(files, taskPath);
      final service = FullBackupService(folder, data.store, tasks);
      final term = Semester(
        id: 'term',
        name: '学期',
        startDate: monday,
        endDate: DateTime(2026, 12, 6),
        week1Monday: monday,
      );
      await data.semesters.insert(term);
      final original = TimeRange(
        start: DateTime(2026, 11, 2, 9),
        end: DateTime(2026, 11, 2, 10),
      );
      final replacement = TimeRange(
        start: DateTime(2026, 11, 3, 9),
        end: DateTime(2026, 11, 3, 10),
      );
      await data.courses.insert(
        Course(
          id: 'course',
          semesterId: term.id,
          name: '数学',
          credits: 2,
          scoreScaleMax: 4,
          slots: [
            CourseSlot(
              weekday: 1,
              startMinute: 540,
              endMinute: 600,
              weeks: [1, 2],
              location: '原教室',
            ),
          ],
          adjustments: [
            CourseAdjustment(
              occurrenceId: 'course:course:0:20261102',
              original: original,
              replacement: replacement,
              location: '新教室',
            ),
          ],
        ),
      );
      await data.assignments.insert(
        Assignment(
          id: 'work',
          courseId: 'course',
          title: '练习',
          dueAt: monday,
          status: AssignmentStatus.submitted,
        ),
      );
      await tasks.insert(
        Task(
          id: 'task',
          title: '整理资料',
          estimatedMinutes: 30,
          priority: TaskPriority.high,
          steps: [TaskStep(id: 'step', title: '归档', done: true)],
        ),
      );
      final record = FinanceRecord(
        id: 'record',
        categoryId: 'food',
        type: FinanceType.expense,
        amountMinor: 1200,
        occurredAt: monday,
        reimbursement: ReimbursementStatus.pending,
        receipt: _png,
      );
      await data.records.insert(record);

      final encoded = (await service.snapshot()).encode();
      final copy = FullBackup.decode(encoded);
      expect(copy.counts['receipts'], 1);
      final invalid = encoded.sublist(0, encoded.length - 1);
      expect(() => FullBackup.decode(invalid), throwsFormatException);
      await data.records.remove(record.id);
      await data.records.insert(record);
      expect((await data.records.getById(record.id))!.receipt, _png);
      await tasks.remove('task');
      await data.records.remove(record.id);

      await service.restore(copy);
      final reopened = CampusData(CampusStore(files, campusPath));
      addTearDown(reopened.dispose);
      final reopenedTasks = FileTaskRepository(files, taskPath);
      expect((await reopenedTasks.getById('task'))!.steps.single.done, isTrue);
      expect(
        (await reopened.assignments.getById('work'))!.status,
        AssignmentStatus.submitted,
      );
      expect((await reopened.records.getById(record.id))!.receipt, _png);
      expect(await reopened.courseOccurrences(monday), isEmpty);
      expect(
        (await reopened.courseOccurrences(replacement.start)).single.location,
        '新教室',
      );
      expect(
        (await reopened.courseOccurrences(
          DateTime(2026, 11, 9),
        )).single.location,
        '原教室',
      );
      expect(
        await folder.list().any(
          (file) => file.path.contains('before-restore-'),
        ),
        isTrue,
      );
    },
  );

  test(
    'failed task replacement rolls campus and tasks back as a complete set',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'v1-restore-failure',
      );
      addTearDown(() => folder.delete(recursive: true));
      final ops = _FailTaskReplaceOnce();
      final files = FileJsonDocumentStore(files: ops);
      final campusPath = '${folder.path}/campus.json';
      final taskPath = '${folder.path}/tasks.json';
      final data = CampusData(CampusStore(files, campusPath));
      addTearDown(data.dispose);
      final tasks = FileTaskRepository(files, taskPath);
      final service = FullBackupService(folder, data.store, tasks);

      final incoming = await service.snapshot();
      await data.semesters.insert(
        Semester(
          id: 'current',
          name: '本地',
          startDate: monday,
          endDate: DateTime(2026, 12, 6),
          week1Monday: monday,
        ),
      );
      await tasks.insert(
        Task(id: 'current', title: '本地任务', estimatedMinutes: 30),
      );
      ops.armed = true;
      await expectLater(
        service.restore(incoming),
        throwsA(isA<FileSystemException>()),
      );
      expect((await tasks.list()).single.id, 'current');
      expect((await data.semesters.list()).single.id, 'current');
      expect(
        (await FileTaskRepository(files, taskPath).list()).single.id,
        'current',
      );
      expect(
        (await CampusStore(files, campusPath).rows('semesters')).single['id'],
        'current',
      );
      expect(
        await File('${folder.path}/restore-pending.json').exists(),
        isFalse,
      );
    },
  );
}
