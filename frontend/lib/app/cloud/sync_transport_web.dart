import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'sync_response.dart';

@JS('studentLifeRequest')
external JSPromise<_WebResponse> _request(
  JSString method,
  JSString path,
  JSString headers,
  JSUint8Array? body,
  JSNumber limit,
);

extension type _WebResponse(JSObject _) implements JSObject {
  external JSNumber get status;
  external JSString? get etag;
  external JSBoolean get tooLarge;
  external JSUint8Array get bytes;
}

Future<SyncResponse> requestSync(
  Uri uri,
  String method,
  Map<String, String> headers,
  List<int>? body,
  int limit,
) async {
  final _WebResponse response;
  try {
    response = await _request(
      method.toJS,
      uri.toString().toJS,
      jsonEncode(headers).toJS,
      body == null ? null : Uint8List.fromList(body).toJS,
      limit.toJS,
    ).toDart;
  } catch (_) {
    throw const SyncConnectionException();
  }
  final status = response.status.toDartInt;
  if (response.tooLarge.toDart && status >= 200 && status < 300) {
    throw const FormatException('服务器返回的数据超过大小上限。');
  }
  return SyncResponse(status, response.etag?.toDart, response.bytes.toDart);
}
