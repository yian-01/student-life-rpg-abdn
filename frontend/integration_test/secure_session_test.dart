import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:student_life_rpg/app/cloud/cloud_sync_controller.dart';
import 'package:student_life_rpg/app/cloud/sync_api.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/app/data/full_backup.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

// Only authentication is a fixture. Session persistence uses the actual native
// secure-storage plugin and account files use a separate temporary directory.
class _Authentication extends HttpCloudSyncApi {
  @override
  Future<CloudSession> authenticate(
    Uri origin, {
    required String email,
    required String password,
    required bool register,
    String code = '',
  }) async => CloudSession(origin, 'a' * 32, email, 'b' * 43);

  @override
  Future<void> revoke(CloudSession session) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native vault survives controller recreation and clears on logout',
    (tester) async {
      final sessions = SecureCloudSessionStore(
        storageKey:
            'student-life-test-session-${DateTime.now().microsecondsSinceEpoch}',
      );
      final root = await Directory.systemTemp.createTemp('student-life-vault-');
      var active = root;
      final controllers = <CloudSyncController>[];
      CloudSyncController device() {
        final controller = CloudSyncController(
          api: _Authentication(),
          sessions: sessions,
          rootDirectory: () async => root,
          switchDirectory: (directory) => active = directory ?? root,
          activeBackup: () async => FullBackupService(
            active,
            CampusStore(
              const FileJsonDocumentStore(),
              '${active.path}/campus.json',
            ),
            FileTaskRepository(
              const FileJsonDocumentStore(),
              '${active.path}/tasks.json',
            ),
          ),
        );
        controllers.add(controller);
        return controller;
      }

      try {
        expect(await sessions.read(), isNull);
        final first = device();
        await first.signIn(
          server: 'https://api.example.test',
          email: 'native-vault@example.test',
          password: 'fixture only, never sent to a server',
          register: false,
        );
        expect(first.session, isNotNull, reason: first.notice);
        final persisted = first.session!.encode();
        final accountDirectory = active;
        first.dispose();
        controllers.remove(first);
        final restored = device();
        await restored.initialize();
        expect(restored.session?.encode(), persisted, reason: restored.notice);
        expect(active.path, accountDirectory.path);
        await restored.signOut();
        expect(restored.session, isNull, reason: restored.notice);
        expect(await sessions.read(), isNull);
        expect(await accountDirectory.exists(), isFalse);
      } finally {
        for (final controller in controllers) {
          controller.dispose();
        }
        await sessions.clear();
        await root.delete(recursive: true);
      }
    },
  );
}
