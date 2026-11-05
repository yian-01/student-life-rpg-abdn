import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

/// 双坏（Task + Campus 同时损坏）组合测试。
///
/// 验证：两个独立的文档同时损坏时，各自的恢复流程互不干扰，
/// 不会因为 Campus 的错误把 Task 的故障掩盖掉，也不会反过来。
void main() {
  late Directory tempDir;
  late String campusPath;
  late String taskPath;
  CampusData openCampus() =>
      CampusData(CampusStore(const FileJsonDocumentStore(), campusPath));
  FileTaskRepository openTasks() =>
      FileTaskRepository(const FileJsonDocumentStore(), taskPath);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dual_corrupt_');
    campusPath = '${tempDir.path}/campus.json';
    taskPath = '${tempDir.path}/tasks.json';
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Task sampleTask(String id) => Task(
        id: id,
        title: '任务$id',
        estimatedMinutes: 30,
        isCompleted: false,
        dueAt: DateTime(2026, 11, 10),
        scheduledRange: TimeRange(
          start: DateTime(2026, 11, 10, 9, 0),
          end: DateTime(2026, 11, 10, 10, 0),
        ),
      );

  test('双坏：Task 和 Campus 同时损坏时各自独立报错，互不掩盖', () async {
    // 正常写入两份有效数据，制造 .bak
    final campus = openCampus();
    await campus.semesters.insert(
      _semester(),
    );
    await campus.courses.insert(_course());
    // 多一次写入，让 .bak 有内容
    await campus.courses.insert(_course(id: 'cs102'));
    final campusBak = await File('$campusPath.bak').readAsString();

    final tasks = openTasks();
    await tasks.insert(sampleTask('t1'));
    // 再 insert 一次，让主文件 = [t1, t2]，.bak = [t1]
    await tasks.insert(sampleTask('t2'));
    final taskBak = await File('$taskPath.bak').readAsString();

    // 同时破坏两份主文件
    await File(campusPath).writeAsString('{damaged campus');
    await File(taskPath).writeAsString('{damaged tasks');

    // 分别从新建实例读取，各自独立抛 FormatException
    final campusCold = openCampus();
    await expectLater(campusCold.store.initialize(), throwsFormatException);

    final tasksCold = openTasks();
    await expectLater(tasksCold.list(), throwsFormatException);

    // 损坏主文件和有效 .bak 均保留
    expect(await File(campusPath).readAsString(), '{damaged campus');
    expect(await File(taskPath).readAsString(), '{damaged tasks');
    expect(await File('$campusPath.bak').readAsString(), campusBak);
    expect(await File('$taskPath.bak').readAsString(), taskBak);
    expect(await File('$campusPath.corrupt').exists(), isFalse);
    expect(await File('$taskPath.corrupt').exists(), isFalse);

    // 各自显式恢复互不影响
    await campusCold.store.recoverFromBackup();
    await tasksCold.recoverFromBackup();

    expect(await File('$campusPath.corrupt').exists(), isTrue);
    expect(await File('$taskPath.corrupt').exists(), isTrue);

    // 恢复后各自读到 .bak 里的上一版数据
    expect((await campusCold.semesters.list()).single.id, 'sem-1');
    expect((await tasksCold.list()).length, 1); // .bak 只有 [t1]
    expect((await tasksCold.list()).single.id, 't1');

    campus.dispose();
    campusCold.dispose();
  });
}

_semester() => Semester(
      id: 'sem-1',
      name: '2026 秋季',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2027, 1, 15),
      week1Monday: DateTime(2026, 8, 31),
    );

_course({String id = 'cs101'}) => Course(
      id: id,
      semesterId: 'sem-1',
      name: '计算机基础',
      credits: 3,
      gradePoint: null,
      scoreScaleMax: 4,
      slots: [
        CourseSlot(
          weekday: 1,
          startMinute: 540,
          endMinute: 600,
          weeks: [1, 3],
        ),
      ],
    );
