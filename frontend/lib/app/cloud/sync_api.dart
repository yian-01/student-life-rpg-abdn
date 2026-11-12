import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../data/full_backup.dart';

class CloudSession {
  const CloudSession(this.origin, this.id, this.email, this.token);

  factory CloudSession.decode(Uri origin, Object? value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(value['id'] as String) ||
        value['email'] is! String ||
        (value['email'] as String).isEmpty ||
        value['token'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value['token'] as String)) {
      throw const FormatException('服务器返回了无效的账号。');
    }
    return CloudSession(
      origin,
      value['id'] as String,
      value['email'] as String,
      value['token'] as String,
    );
  }

  final Uri origin;
  final String id;
  final String email;
  final String token;

  String encode() => jsonEncode({
    'origin': origin.toString(),
    'id': id,
    'email': email,
    'token': token,
  });

  static CloudSession restore(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> || value['origin'] is! String) {
      throw const FormatException('本机登录信息已损坏。');
    }
    return CloudSession.decode(
      parseSyncOrigin(value['origin'] as String),
      value,
    );
  }
}

Uri parseSyncOrigin(String text) {
  final uri = Uri.tryParse(text.trim());
  final devOrigin =
      kDebugMode &&
      uri?.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri?.host);
  if (uri == null ||
      (uri.scheme != 'https' && !devOrigin) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('请输入云同步服务的 HTTPS 地址（不含路径）。');
  }
  return uri.replace(path: '');
}

class SyncApiException implements Exception {
  const SyncApiException(this.status, this.code);
  final int status;
  final String code;

  String get message => switch (code) {
    'invalid_credentials' when status == 401 => '邮箱或密码不正确。',
    'invalid_credentials' => '请检查邮箱和密码格式，密码至少需要 12 个字符。',
    'signup_code_required' => '注册邀请码不正确。',
    'account_exists' => '该邮箱已注册，请登录。',
    'session_expired' => '登录已过期，请重新登录同一账号。本机修改仍已保存。',
    'try_later' => '尝试次数过多，请稍后再试。',
    'too_large' => '数据超过同步大小上限（64 MB）。',
    _ => '云同步服务暂时无法完成操作（HTTP $status）。',
  };
}

class RemoteSnapshot {
  const RemoteSnapshot(this.revision, this.bytes, {this.unchanged = false});
  final int revision;
  final Uint8List? bytes;
  final bool unchanged;
}

abstract interface class CloudSyncApi {
  Future<CloudSession> authenticate(
    Uri origin, {
    required String email,
    required String password,
    required bool register,
    String code = '',
  });

  Future<RemoteSnapshot> fetch(CloudSession session, {int? knownRevision});

  /// Returns null when another device has advanced the revision.
  Future<int?> upload(
    CloudSession session, {
    required int expectedRevision,
    required String uploadId,
    required Uint8List bytes,
  });

  Future<void> revoke(CloudSession session);
}

class HttpCloudSyncApi implements CloudSyncApi {
  static const _timeout = Duration(seconds: 45);

  @override
  Future<CloudSession> authenticate(
    Uri origin, {
    required String email,
    required String password,
    required bool register,
    String code = '',
  }) => _request(
    origin,
    'POST',
    register ? '/v1/register' : '/v1/login',
    body: utf8.encode(
      jsonEncode({'email': email, 'password': password, 'code': code}),
    ),
    json: true,
    read: (response) async {
      if (response.statusCode != (register ? 201 : 200)) {
        await _throwResponse(response);
      }
      final raw = await _readBytes(response, 4096);
      return CloudSession.decode(origin, jsonDecode(utf8.decode(raw)));
    },
  );

  @override
  Future<RemoteSnapshot> fetch(CloudSession session, {int? knownRevision}) =>
      _request(
        session.origin,
        'GET',
        '/v1/snapshot',
        session: session,
        headers: {
          if (knownRevision != null)
            HttpHeaders.ifNoneMatchHeader: '"$knownRevision"',
        },
        read: (response) async {
          switch (response.statusCode) {
            case 304 when knownRevision != null:
              if (_revision(response) != knownRevision) {
                throw const FormatException('云端版本校验失败。');
              }
              return RemoteSnapshot(knownRevision, null, unchanged: true);
            case 204:
              if (_revision(response) != 0) {
                throw const FormatException('云端快照缺失。');
              }
              return const RemoteSnapshot(0, null);
            case 200:
              final revision = _revision(response);
              if (revision == 0) {
                throw const FormatException('云端快照版本无效。');
              }
              final bytes = await _readBytes(response, maxBackupBytes);
              return RemoteSnapshot(revision, bytes);
            default:
              return _throwResponse(response);
          }
        },
      );

  @override
  Future<int?> upload(
    CloudSession session, {
    required int expectedRevision,
    required String uploadId,
    required Uint8List bytes,
  }) => _request(
    session.origin,
    'PUT',
    '/v1/snapshot',
    session: session,
    headers: {
      HttpHeaders.ifMatchHeader: '"$expectedRevision"',
      'X-Upload-Id': uploadId,
    },
    body: bytes,
    read: (response) async {
      if (response.statusCode == 409) return null;
      if (response.statusCode != 204) await _throwResponse(response);
      final revision = _revision(response);
      if (revision != expectedRevision + 1) {
        throw const FormatException('云端保存确认版本无效。');
      }
      return revision;
    },
  );

  @override
  Future<void> revoke(CloudSession session) => _request(
    session.origin,
    'DELETE',
    '/v1/session',
    session: session,
    read: (response) async {
      if (response.statusCode != 204 && response.statusCode != 401) {
        await _throwResponse(response);
      }
    },
  );

  Future<T> _request<T>(
    Uri origin,
    String method,
    String path, {
    CloudSession? session,
    Map<String, String> headers = const {},
    List<int>? body,
    bool json = false,
    required Future<T> Function(HttpClientResponse response) read,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.openUrl(method, origin.resolve(path));
        request.followRedirects = false;
        if (session != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${session.token}',
          );
        }
        headers.forEach(request.headers.set);
        if (body != null) {
          request.headers.contentType = json
              ? ContentType.json
              : ContentType.binary;
          request.contentLength = body.length;
          request.add(body);
        }
        return read(await request.close());
      })().timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }

  static int _revision(HttpClientResponse response) {
    final header = response.headers.value(HttpHeaders.etagHeader) ?? '';
    final match = RegExp(r'^"(0|[1-9][0-9]{0,14})"$').firstMatch(header);
    if (match == null) throw const FormatException('服务器版本标记无效。');
    return int.parse(match[1]!);
  }

  static Future<Uint8List> _readBytes(
    HttpClientResponse response,
    int limit,
  ) async {
    if (response.contentLength > limit) {
      throw const FormatException('服务器返回的数据超过大小上限。');
    }
    final result = BytesBuilder(copy: false);
    await for (final part in response) {
      if (result.length + part.length > limit) {
        throw const FormatException('服务器返回的数据超过大小上限。');
      }
      result.add(part);
    }
    return result.takeBytes();
  }

  static Future<Never> _throwResponse(HttpClientResponse response) async {
    var code = '';
    try {
      final data = jsonDecode(utf8.decode(await _readBytes(response, 4096)));
      if (data is Map<String, dynamic> && data['error'] is String) {
        code = data['error'] as String;
      }
    } on FormatException {
      // A reverse proxy may send an HTML error response.
    }
    throw SyncApiException(response.statusCode, code);
  }
}
