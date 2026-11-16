import 'dart:typed_data';

class SyncResponse {
  const SyncResponse(this.statusCode, this.etag, this.bytes);

  final int statusCode;
  final String? etag;
  final Uint8List bytes;
}

class SyncConnectionException implements Exception {
  const SyncConnectionException();
}
