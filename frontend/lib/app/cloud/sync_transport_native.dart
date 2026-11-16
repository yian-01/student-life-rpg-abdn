import 'dart:io';
import 'dart:typed_data';

import 'sync_response.dart';

Future<SyncResponse> requestSync(
  Uri uri,
  String method,
  Map<String, String> headers,
  List<int>? body,
  int limit,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    return await (() async {
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close();
      final status = response.statusCode;
      final success = (status >= 200 && status < 300) || status == 304;
      final cap = success ? limit : 4096;
      final bytes = BytesBuilder(copy: false);
      if (cap > 0) {
        var oversized = response.contentLength > cap;
        if (!oversized) {
          await for (final part in response) {
            if (bytes.length + part.length > cap) {
              oversized = true;
              break;
            }
            bytes.add(part);
          }
        }
        if (oversized) {
          if (success) {
            throw const FormatException('服务器返回的数据超过大小上限。');
          }
          bytes.clear();
        }
      }
      return SyncResponse(
        status,
        response.headers.value(HttpHeaders.etagHeader),
        bytes.takeBytes(),
      );
    })().timeout(const Duration(seconds: 45));
  } on HandshakeException {
    throw const FormatException('无法验证云同步服务的 HTTPS 证书。');
  } on SocketException {
    throw const SyncConnectionException();
  } on HttpException {
    throw const SyncConnectionException();
  } finally {
    client.close(force: true);
  }
}
