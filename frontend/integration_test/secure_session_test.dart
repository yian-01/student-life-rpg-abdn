import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:student_life_rpg/app/cloud/cloud_sync_controller.dart';
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/app/cloud/sync_api.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/app/data/full_backup.dart';
import 'package:student_life_rpg/features/schedule/repositories/file_task_repository.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';
import 'package:student_life_rpg/features/timetable_capture/scnu_web_session.dart';

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

  testWidgets(
    'school browser cookies stay private across account profiles',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'student-life-browser-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/seed') {
          request.response.cookies.add(
            Cookie('school_session', 'fixture_only')
              ..httpOnly = false
              ..path = '/',
          );
        }
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<html><body>Private browser fixture</body></html>',
        );
        await request.response.close();
      });
      final origin = 'http://127.0.0.1:${server.port}';
      Future<String> read(String account, String path) async {
        final directory = await Directory('${root.path}/$account').create();
        AppData.switchDirectory(directory);
        final environment = await ScnuWebSession.openEnvironment();
        final loaded = Completer<InAppWebViewController>();
        final browser = HeadlessInAppWebView(
          webViewEnvironment: environment,
          initialSettings: ScnuWebSession.browserSettings(),
          initialUrlRequest: URLRequest(url: WebUri('$origin/$path')),
          shouldOverrideUrlLoading: (_, _) async =>
              NavigationActionPolicy.ALLOW,
          onReceivedError: (_, request, error) {
            if (!loaded.isCompleted) {
              loaded.completeError(
                StateError('Local browser fixture: ${error.description}'),
              );
            }
          },
          onLoadStop: (controller, url) {
            if (url.toString() == '$origin/$path' && !loaded.isCompleted) {
              loaded.complete(controller);
            }
          },
        );
        try {
          await browser.run();
          final controller = await loaded.future.timeout(
            const Duration(seconds: 30),
          );
          return (await controller.evaluateJavascript(
                source: 'document.cookie',
              ))
              as String;
        } finally {
          await browser.dispose();
          await environment?.dispose();
        }
      }

      try {
        expect(
          await read('account-a', 'seed'),
          contains('school_session=fixture_only'),
        );
        expect(await read('account-b', 'check'), isEmpty);
        expect(await read('account-a', 'check'), isEmpty);
      } finally {
        AppData.switchDirectory(null);
        await server.close(force: true);
        // WebView2 may release its profile file handles shortly after disposal.
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (await root.exists()) {
          try {
            await root.delete(recursive: true);
          } on FileSystemException {
            if (DateTime.now().isAfter(deadline)) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    },
    skip: !Platform.isWindows,
  );
}
