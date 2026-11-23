import 'dart:convert';
import 'dart:math';
import '../cloud/sync_api.dart';
import '../cloud/sync_transport.dart';

class Person {
  const Person(this.id, this.nickname, this.avatar, this.bio, this.title);
  factory Person.decode(Map<String, dynamic> value) => Person(
    value['id'] as String,
    value['nickname'] as String,
    value['avatar'] as String,
    value['bio'] as String,
    value['title'] as String,
  );
  final String id, nickname, avatar, bio, title;
}

class SocialException implements Exception {
  const SocialException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef SocialTransport =
    Future<SyncResponse> Function(
      Uri,
      String,
      Map<String, String>,
      List<int>?,
      int,
    );

class SocialApi {
  const SocialApi({this.transport = requestSync});
  final SocialTransport transport;

  static String messageId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> call(
    CloudSession session,
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, String>? query,
  }) async {
    try {
      final result = await transport(
        session.origin.replace(path: '/v1/$path', queryParameters: query),
        method,
        {
          'Authorization': 'Bearer ${session.token}',
          if (data != null) 'Content-Type': 'application/json',
        },
        data == null ? null : utf8.encode(jsonEncode(data)),
        256 * 1024,
      );
      final raw = jsonDecode(utf8.decode(result.bytes));
      if (result.statusCode < 200 || result.statusCode >= 300) {
        final code = raw is Map ? raw['error'] : null;
        throw SocialException(switch (code) {
          'session_expired' => '登录已过期，请重新登录。',
          'person_not_found' => '没有找到这个 ID，请检查后重试。',
          'cannot_add_self' => '这是你自己的 ID。',
          'request_not_found' => '好友申请已失效，请刷新。',
          'friends_only' => '成为好友后才能收发私信，请刷新好友列表。',
          'try_later' => '操作太频繁，请稍后再试。',
          'invalid_social_input' => '请检查内容长度及资料格式。',
          'message_id_reused' => '这条消息的重试内容已改变，请重新发送。',
          _ => '暂时无法完成操作，请稍后重试。',
        });
      }
      if (raw is! Map<String, dynamic>) throw const FormatException();
      return raw;
    } on SyncConnectionException {
      throw const SocialException('网络连接失败，内容仍保留，可以重试。');
    } on FormatException {
      throw const SocialException('无法读取服务器回复，请稍后重试。');
    }
  }

  static List<Person> people(Object? raw) => (raw as List)
      .map((p) => Person.decode(p as Map<String, dynamic>))
      .toList();
}
