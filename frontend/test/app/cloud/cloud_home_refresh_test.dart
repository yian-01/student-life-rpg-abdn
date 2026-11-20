import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/app/cloud/cloud_sync_controller.dart';
import 'package:student_life_rpg/app/cloud/sync_api.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/app/data/full_backup.dart';
import 'package:student_life_rpg/app/student_life_app.dart';
import 'package:student_life_rpg/features/schedule/models/task.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

class _Sessions implements CloudSessionStore {
  CloudSession? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<CloudSession?> read() async => value;
  @override
  Future<void> save(CloudSession session) async => value = session;
}

class _Cloud extends HttpCloudSyncApi {
  RemoteSnapshot snapshot = const RemoteSnapshot(0, null);
  @override
  Future<CloudSession> authenticate(
    Uri origin, {
    required String email,
    required String password,
    required bool register,
    String code = '',
  }) async => CloudSession(origin, 'account', email, 'token');
  @override
  Future<RemoteSnapshot> fetch(
    CloudSession session, {
    int? knownRevision,
  }) async => snapshot;
  @override
  Future<void> revoke(CloudSession session) async {}
  @override
  Future<int?> upload(
    CloudSession session, {
    required int expectedRevision,
    required String uploadId,
    required Uint8List bytes,
  }) async => throw StateError('The test must pull, not upload');
}

void main() {
  testWidgets(
    'remote pull refreshes the already visible home without navigation',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('cloud-home-refresh-');
      const store = FileJsonDocumentStore();
      final api = _Cloud();
      var directory = root;
      late CampusData campus;
      late FileTaskRepository tasks;
      final opened = <CampusData>[];
      void useDirectory(Directory? next) {
        directory = next ?? root;
        campus = CampusData(
          CampusStore(store, '${directory.path}/campus.json'),
        );
        tasks = FileTaskRepository(store, '${directory.path}/tasks.json');
        opened.add(campus);
        AppData.useCampusData(campus);
        AppData.useTaskRepository(tasks);
      }

      useDirectory(null);
      final cloud =
          CloudSyncController(
              api: api,
              sessions: _Sessions(),
              rootDirectory: () async => root,
              switchDirectory: useDirectory,
              activeBackup: () async =>
                  FullBackupService(directory, campus.store, tasks),
            )
            ..routeChanged(safe: true)
            ..lifecycleChanged(foreground: false);
      addTearDown(() {
        cloud.dispose();
        for (final data in opened) {
          data.dispose();
        }
        root.deleteSync(recursive: true);
      });
      await tester.runAsync(
        () => cloud.signIn(
          server: 'https://api.example.test',
          email: 'fixture@example.test',
          password: 'fixture password',
          register: false,
        ),
      );
      expect(cloud.session, isNotNull, reason: cloud.notice);
      await tester.runAsync(() async {
        Future<void> waitForText(String text) async {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (find.text(text).evaluate().isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            await tester.pump(const Duration(milliseconds: 16));
            if (DateTime.now().isAfter(deadline)) {
              fail('Home did not finish loading file-backed data');
            }
          }
        }

        await tester.pumpWidget(StudentLifeApp(cloud: cloud));
        await tester.scrollUntilVisible(
          find.text('待办事项'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await waitForText('暂时没有未完成事项');
        expect(find.text('暂时没有未完成事项'), findsOneWidget);
        api.snapshot = RemoteSnapshot(
          1,
          FullBackup.validate(
            DateTime(2026, 11, 21),
            jsonEncode(CampusStore.emptyDocument()),
            jsonEncode({
              'schemaVersion': 1,
              'entityType': 'Task',
              'records': [
                Task(
                  id: 'other-device-task',
                  title: '来自另一设备的任务',
                  estimatedMinutes: 25,
                ).toJson(),
              ],
            }),
          ).encode(),
        );
        cloud.lifecycleChanged(foreground: true);
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (cloud.working) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Foreground sync did not finish');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        cloud.lifecycleChanged(foreground: false);
        expect(cloud.dataRevision, 1);
        expect(cloud.notice, isNull);
        await tester.pump();
        await waitForText('来自另一设备的任务');
        expect(find.text('来自另一设备的任务'), findsOneWidget);
        expect(find.text('暂时没有未完成事项'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );
}
