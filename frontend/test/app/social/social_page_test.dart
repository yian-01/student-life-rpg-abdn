import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/cloud/cloud_scope.dart';
import 'package:student_life_rpg/app/cloud/cloud_page.dart';
import 'package:student_life_rpg/app/cloud/cloud_sync_controller.dart';
import 'package:student_life_rpg/app/cloud/sync_api.dart';
import 'package:student_life_rpg/app/cloud/sync_response.dart';
import 'package:student_life_rpg/app/social/social_api.dart';
import 'package:student_life_rpg/app/social/social_page.dart';
import 'package:student_life_rpg/app/social/chat_page.dart';

class _Cloud extends CloudSyncController {
  CloudSession? current = CloudSession(
    Uri.parse('https://social.example.test'),
    'a' * 32,
    'private@example.test',
    'fixture',
  );
  String? submitted;
  @override
  CloudSession? get session => current;
  @override
  Future<void> signIn({
    required String server,
    required String email,
    required String password,
    required bool register,
    String code = '',
  }) async {
    submitted = password;
  }

  void leave() {
    current = null;
    notifyListeners();
  }
}

Map<String, dynamic> _profile() => {
  'id': '0123456789',
  'nickname': '测试同学',
  'avatar': 'cat',
  'bio': '',
  'title': '课屿居民',
};
SyncResponse _reply(Object value, [int status = 200]) => SyncResponse(
  status,
  null,
  Uint8List.fromList(utf8.encode(jsonEncode(value))),
);
Widget _wrap(_Cloud cloud, Widget child) => CloudScope(
  controller: cloud,
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('received message text is accessible and removed after logout', (
    tester,
  ) async {
    final cloud = _Cloud();
    addTearDown(cloud.dispose);
    final semantics = tester.ensureSemantics();
    final api = SocialApi(
      transport: (uri, method, headers, bytes, limit) async => _reply({
        'messages': [
          {'id': 1, 'mine': false, 'text': '一条私信', 'createdAt': 1795417000},
        ],
        'hasMore': false,
      }),
    );
    await tester.pumpWidget(
      _wrap(
        cloud,
        ChatPage(
          session: cloud.session!,
          person: Person.decode(_profile()),
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('一条私信')), findsWidgets);
    cloud.leave();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('一条私信')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });
  testWidgets(
    'profile shows public ID, saves real fields and clears on logout',
    (tester) async {
      final cloud = _Cloud();
      addTearDown(cloud.dispose);
      Map<String, dynamic>? saved;
      final api = SocialApi(
        transport: (uri, method, headers, bytes, limit) async {
          expect(headers['Authorization'], 'Bearer fixture');
          if (uri.path.endsWith('/friends')) return _reply({'friends': []});
          if (uri.path.endsWith('/friend-requests')) {
            return _reply({'incoming': [], 'outgoing': []});
          }
          if (method == 'PUT') {
            saved = jsonDecode(utf8.decode(bytes!)) as Map<String, dynamic>;
          }
          return _reply({..._profile(), ...?saved});
        },
      );
      await tester.pumpWidget(_wrap(cloud, SocialPage(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('ID 0123456789'), findsOneWidget);
      expect(find.text('private@example.test'), findsNothing);
      final nickname = find.widgetWithText(TextFormField, '昵称');
      await tester.ensureVisible(nickname);
      await tester.enterText(nickname, '新的名字');
      final save = find.text('保存个人资料');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved?['nickname'], '新的名字');
      expect(saved?.containsKey('id'), isFalse);
      cloud.leave();
      await tester.pumpAndSettle();
      expect(find.text('ID 0123456789'), findsNothing);
      expect(find.text('登录后查看个人空间'), findsOneWidget);
    },
  );

  testWidgets('chat retains failed send and retries with same operation ID', (
    tester,
  ) async {
    final cloud = _Cloud();
    addTearDown(cloud.dispose);
    final sent = <Map<String, dynamic>>[];
    final api = SocialApi(
      transport: (uri, method, headers, bytes, limit) async {
        if (method == 'GET') return _reply({'messages': [], 'hasMore': false});
        sent.add(jsonDecode(utf8.decode(bytes!)) as Map<String, dynamic>);
        if (sent.length == 1) throw const SyncConnectionException();
        return _reply({'id': 1}, 201);
      },
    );
    await tester.pumpWidget(
      _wrap(
        cloud,
        ChatPage(
          session: cloud.session!,
          person: Person.decode(_profile()),
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '你好呀');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.text('重试发送'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '你好呀',
    );
    await tester.tap(find.text('重试发送'));
    await tester.pumpAndSettle();
    expect(sent.length, 2);
    expect(sent[0], sent[1]);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    cloud.leave();
    await tester.pumpAndSettle();
    expect(find.text('当前账号已退出，请重新登录。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone-sized personal space lays out without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cloud = _Cloud();
    addTearDown(cloud.dispose);
    final api = SocialApi(
      transport: (uri, method, headers, bytes, limit) async => _reply(
        uri.path.endsWith('/profile')
            ? _profile()
            : uri.path.endsWith('/friends')
            ? {
                'friends': [_profile()],
              }
            : {
                'incoming': [_profile()],
                'outgoing': [_profile()],
              },
      ),
    );
    await tester.pumpWidget(_wrap(cloud, SocialPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('好友 · 1'));
    await tester.pumpAndSettle();
    expect(find.text('查找好友'), findsOneWidget);
    await tester.tap(find.text('申请 · 1'));
    await tester.pumpAndSettle();
    expect(find.text('接受'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password form rejects seven characters and accepts eight', (
    tester,
  ) async {
    final cloud = _Cloud()..current = null;
    addTearDown(cloud.dispose);
    await tester.pumpWidget(_wrap(cloud, const CloudPage()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '云同步服务'),
      'https://social.example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '邮箱'),
      'user@example.test',
    );
    final password = find.widgetWithText(TextFormField, '密码');
    await tester.enterText(password, 'seven77');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.text('密码至少需要 8 个字符'), findsOneWidget);
    expect(cloud.submitted, isNull);
    await tester.enterText(password, 'eight888');
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(cloud.submitted, 'eight888');
  });
}
