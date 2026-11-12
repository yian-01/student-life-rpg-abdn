import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/cloud/cloud_sync_controller.dart';
import 'package:student_life_rpg/app/cloud/sync_api.dart';
import 'package:student_life_rpg/app/cloud/sync_dataset.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/app/data/full_backup.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/finance/models/budget.dart';
import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

class _MemorySession implements CloudSessionStore {
  CloudSession? session;

  @override
  Future<void> clear() async {
    session = null;
  }

  @override
  Future<CloudSession?> read() async => session;

  @override
  Future<void> save(CloudSession value) async {
    session = value;
  }
}

class _DropResponseApi extends HttpCloudSyncApi {
  bool dropNextUpload = false;

  @override
  Future<int?> upload(
    CloudSession session, {
    required int expectedRevision,
    required String uploadId,
    required Uint8List bytes,
  }) async {
    final revision = await super.upload(
      session,
      expectedRevision: expectedRevision,
      uploadId: uploadId,
      bytes: bytes,
    );
    if (dropNextUpload) {
      dropNextUpload = false;
      throw const SocketException('connection dropped after server committed');
    }
    return revision;
  }
}

class _Device {
  _Device(this.root, {CloudSyncApi? api, _MemorySession? sessions}) {
    cloud = CloudSyncController(
      api: api,
      sessions: sessions ?? _MemorySession(),
      rootDirectory: () async => root,
      activeBackup: () async => files,
      guestBackup: () async => _at(root),
      switchDirectory: (path) => files = _at(path ?? root),
    )..routeChanged(safe: true);
  }

  final Directory root;
  late final CloudSyncController cloud;
  late FullBackupService files = _at(root);
  CampusData get campus => CampusData(files.campus);

  static FullBackupService _at(Directory path) => FullBackupService(
    path,
    CampusStore(const FileJsonDocumentStore(), '${path.path}/campus.json'),
    FileTaskRepository(
      const FileJsonDocumentStore(),
      '${path.path}/tasks.json',
    ),
  );

  Future<void> login(
    String origin, {
    bool register = false,
    String email = 'sync@example.test',
  }) => cloud.signIn(
    server: origin,
    email: email,
    password: 'only a fixture password',
    register: register,
  );
}

Task _task(String id, {String? title}) => Task(
  id: id,
  title: title ?? id,
  estimatedMinutes: 25,
  priority: TaskPriority.high,
  steps: [TaskStep(id: 'step-$id', title: '整理笔记', done: true)],
);

Future<void> _seed(_Device device) async {
  final campus = device.campus;
  final date = DateTime(2026, 11, 10, 12);
  final time = TimeRange(start: date, end: date.add(const Duration(hours: 1)));
  await campus.semesters.insert(
    Semester(
      id: 'semester',
      name: '秋季学期',
      startDate: DateTime(2026, 10, 26),
      endDate: DateTime(2026, 11, 29),
      week1Monday: DateTime(2026, 10, 26),
    ),
  );
  await campus.courses.insert(
    Course(
      id: 'course',
      semesterId: 'semester',
      name: '数据结构',
      credits: 3,
      gradePoint: 4.6,
      scoreScaleMax: 5,
      slots: [
        CourseSlot(weekday: 2, startMinute: 720, endMinute: 780, weeks: [3]),
      ],
    ),
  );
  await campus.assignments.insert(
    Assignment(
      id: 'assignment',
      courseId: 'course',
      title: '第 1 次作业',
      dueAt: date,
      status: AssignmentStatus.submitted,
    ),
  );
  await campus.exams.insert(
    Exam(id: 'exam', courseId: 'course', title: '考试', range: time),
  );
  await campus.events.insert(Event(id: 'event', title: '社团活动', range: time));
  await campus.categories.insert(
    FinanceCategory(id: 'study', name: '学习用品', type: FinanceType.expense),
  );
  await campus.budgets.put(
    Budget(categoryId: 'study', month: date, amountMinor: 40000),
  );
  await campus.records.insert(
    FinanceRecord(
      id: 'record',
      categoryId: 'study',
      type: FinanceType.expense,
      amountMinor: 1599,
      occurredAt: date,
      reimbursement: ReimbursementStatus.pending,
      receipt:
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XJ1sAAAAASUVORK5CYII=',
    ),
  );
  await device.files.tasks.insert(_task('first', title: '复习'));
}

void main() {
  test(
    'full-data device synchronization over the HTTP API',
    () async {
      final root = await Directory.systemTemp.createTemp('campus-sync-');
      addTearDown(() => root.delete(recursive: true));
      final server = await Process.start(
        'python3',
        ['../backend/sync_server.py'],
        environment: {
          'SYNC_DATABASE': '${root.path}/cloud.sqlite3',
          'SYNC_DEV_PORT': '0',
          'SYNC_SIGNUP_CODE': '',
        },
      );
      final stdout = StreamIterator(
        server.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      final stderr = server.stderr.drain<void>();
      addTearDown(() async {
        server.kill();
        await stdout.cancel();
        await server.exitCode;
        await stderr;
      });
      expect(
        await stdout.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      final port = int.parse(stdout.current.split(' ').last);
      final origin = 'http://127.0.0.1:$port';

      final auth = _MemorySession();
      final flaky = _DropResponseApi();
      final desktop = _Device(
        await Directory('${root.path}/desktop').create(),
        api: flaky,
        sessions: auth,
      );
      final mobile = _Device(await Directory('${root.path}/mobile').create());
      final other = _Device(await Directory('${root.path}/other').create());
      addTearDown(desktop.cloud.dispose);
      addTearDown(mobile.cloud.dispose);
      addTearDown(other.cloud.dispose);
      await _seed(desktop);
      final old = SyncDataset(await desktop.files.snapshot());
      expect(old.backup.receipts, hasLength(1));
      for (final table in SyncDataset.tables) {
        expect(old.backup.counts[table], greaterThan(0), reason: table);
      }

      await desktop.login(origin, register: true);
      expect(desktop.cloud.session, isNotNull, reason: desktop.cloud.notice);
      expect((await desktop.files.tasks.list()), isEmpty);
      await desktop.cloud.importGuest();
      expect(desktop.cloud.guestImported, isTrue, reason: desktop.cloud.notice);
      expect(desktop.cloud.lastSync, isNotNull, reason: desktop.cloud.notice);
      await mobile.login(origin);
      await mobile.cloud.sync();
      expect(
        SyncDataset(await mobile.files.snapshot()).sameData(old),
        isTrue,
        reason: mobile.cloud.notice,
      );

      // Two devices can edit different records while offline.
      await desktop.files.tasks.insert(_task('desktop'));
      await mobile.campus.events.insert(
        Event(
          id: 'mobile',
          title: '手机新增',
          range: TimeRange(
            start: DateTime(2026, 11, 10, 12),
            end: DateTime(2026, 11, 10, 13),
          ),
        ),
      );
      await desktop.cloud.sync();
      await mobile.cloud.sync();
      await desktop.cloud.sync();
      expect(await desktop.campus.events.getById('mobile'), isNotNull);
      expect(await mobile.files.tasks.getById('desktop'), isNotNull);

      // On a conflict, keep one version of the row and retain unrelated edits.
      await desktop.files.tasks.update(_task('first', title: '电脑版本'));
      await mobile.files.tasks.update(_task('first', title: '手机版本'));
      await mobile.files.tasks.insert(_task('independent'));
      await desktop.cloud.sync();
      await mobile.cloud.sync();
      expect(mobile.cloud.conflict?.merge.conflicts.single.id, 'first');
      await mobile.cloud.sync(choice: SyncChoice.other);
      await desktop.cloud.sync();
      expect((await desktop.files.tasks.getById('first'))?.title, '电脑版本');
      expect(await desktop.files.tasks.getById('independent'), isNotNull);

      // Losing a response after commit must not resurrect a later cloud deletion.
      await desktop.files.tasks.insert(_task('lost-response'));
      flaky.dropNextUpload = true;
      await desktop.cloud.sync();
      expect(desktop.cloud.notice, contains('暂时连不上'));
      await mobile.cloud.sync();
      expect(await mobile.files.tasks.remove('lost-response'), isTrue);
      await mobile.cloud.sync();
      final restarted = _Device(desktop.root, sessions: auth);
      addTearDown(restarted.cloud.dispose);
      await restarted.cloud.initialize();
      await restarted.cloud.sync();
      expect(await restarted.files.tasks.getById('lost-response'), isNull);
      expect(restarted.cloud.conflict, isNull, reason: restarted.cloud.notice);

      await other.login(origin, register: true, email: 'other@example.test');
      await other.cloud.sync();
      expect((await other.files.tasks.list()), isEmpty);
      expect((await other.campus.records.list()), isEmpty);

      await restarted.cloud.signOut();
      expect(restarted.cloud.session, isNull);
      expect(await restarted.files.tasks.getById('first'), isNotNull);
      expect(await restarted.files.tasks.getById('desktop'), isNull);
      await restarted.login(origin, email: 'other@example.test');
      await restarted.cloud.sync();
      expect(await restarted.files.tasks.list(), isEmpty);
      await restarted.cloud.signOut();
      await restarted.login(origin);
      await restarted.cloud.sync();
      expect(await restarted.files.tasks.getById('desktop'), isNotNull);
    },
    skip: Platform.environment['CAMPUS_SYNC_E2E'] != '1',
  );

  test(
    'course deletion and a new assignment require a whole-version decision',
    () async {
      final root = await Directory.systemTemp.createTemp('campus-merge-');
      addTearDown(() => root.delete(recursive: true));
      final device = _Device(root);
      addTearDown(device.cloud.dispose);
      final campus = device.campus;
      await campus.semesters.insert(
        Semester(
          id: 's',
          name: '测试',
          startDate: DateTime(2026, 11, 2),
          endDate: DateTime(2026, 11, 30),
          week1Monday: DateTime(2026, 11, 2),
        ),
      );
      final course = Course(
        id: 'c',
        semesterId: 's',
        name: '课',
        credits: 1,
        slots: const [],
        scoreScaleMax: 5,
      );
      await campus.courses.insert(course);
      final base = SyncDataset(await device.files.snapshot());
      await campus.courses.remove('c');
      final local = SyncDataset(await device.files.snapshot());
      await campus.courses.insert(course);
      await campus.assignments.insert(
        Assignment(
          id: 'a',
          courseId: 'c',
          title: '作业',
          dueAt: DateTime(2026, 11, 12),
        ),
      );
      final remote = SyncDataset(await device.files.snapshot());
      expect(
        SyncMerge.reconcile(base, local, remote).invalidReferences,
        isTrue,
      );
    },
  );
}
