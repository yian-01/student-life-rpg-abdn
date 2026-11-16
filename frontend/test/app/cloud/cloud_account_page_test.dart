import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/cloud/cloud_page.dart';
import 'package:student_life_rpg/app/cloud/cloud_sync_controller.dart';
import 'package:student_life_rpg/app/cloud/sync_api.dart';
import 'package:student_life_rpg/app/student_life_app.dart';

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

class _AccountPageApi extends HttpCloudSyncApi {
  @override
  Future<CloudSession> authenticate(
    Uri origin, {
    required String email,
    required String password,
    required bool register,
    String code = '',
  }) async => CloudSession(origin, 'fixture-account', email, 'fixture-token');

  @override
  Future<void> revoke(CloudSession session) async {}
}

void main() {
  testWidgets('account page survives sign-in and sign-out', (tester) async {
    final root = Directory.systemTemp.createTempSync('campus-account-page-');
    final cloud = CloudSyncController(
      api: _AccountPageApi(),
      sessions: _MemorySession(),
      rootDirectory: () async => root,
      switchDirectory: (_) {},
    )..lifecycleChanged(foreground: false);
    addTearDown(() => root.deleteSync(recursive: true));
    addTearDown(cloud.dispose);
    const origin = 'https://sync.example.test';
    await tester.pumpWidget(StudentLifeApp(cloud: cloud));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.pushNamed<void>(CloudPage.route));
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsOneWidget);

    await tester.runAsync(
      () => cloud.signIn(
        server: origin,
        email: 'sync@example.test',
        password: 'only a fixture password',
        register: false,
      ),
    );
    await tester.pump();
    expect(find.text('sync@example.test'), findsOneWidget);
    expect(find.text('导入本机 V1.0 数据'), findsOneWidget);
    final accountNavigator = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    expect(accountNavigator.canPop(), isTrue);
    await tester.runAsync(cloud.signOut);
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsOneWidget);
    expect(find.text(origin), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CloudPage), findsNothing);
    expect(cloud.session, isNull);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
