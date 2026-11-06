import 'dart:async';

/// Only an in-app browser that owns the user's authenticated session may
/// implement this interface. Callers never pass cookies, passwords or tokens.
abstract interface class AuthenticatedPageSession {
  /// Load [url] and read the resulting page using this same browser session.
  /// The implementation must stop pending navigation when [timeout] expires.
  Future<PageSnapshot> openAndRead(Uri url, {required Duration timeout});
}

/// Ephemeral data. The final URL and page text may contain private information;
/// neither belongs in logs, screenshots or checked-in fixtures.
class PageSnapshot {
  const PageSnapshot({
    required this.finalUrl,
    required this.text,
    required this.mimeType,
  });

  final Uri finalUrl;
  final String text;
  final String mimeType;
}

enum TimetablePageKind { timetable, login, unsupported }

/// Source-specific classification belongs to the parser/provider adapter.
typedef TimetablePageClassifier = TimetablePageKind Function(PageSnapshot page);

enum CaptureErrorCode {
  invalidUrl,
  loginExpired,
  networkTimeout,
  unsupportedPage,
  cancelled,
  networkUnavailable,
  readFailed,
}

/// Safe to show to the caller: it contains no URL, page text or credentials.
class TimetableCaptureException implements Exception {
  const TimetableCaptureException(this.code);

  final CaptureErrorCode code;

  @override
  String toString() => 'TimetableCaptureException(${code.name})';
}

/// In-memory content for #34. A preview/cancel must not persist this content.
class CapturedTimetablePage {
  const CapturedTimetablePage({required this.text, required this.mimeType});

  final String text;
  final String mimeType;
}

/// Capture with an existing authenticated browser session, then classify the
/// resulting page before handing content to the parser.
Future<CapturedTimetablePage> captureTimetablePage({
  required Uri url,
  required AuthenticatedPageSession session,
  required TimetablePageClassifier classify,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
    throw const TimetableCaptureException(CaptureErrorCode.invalidUrl);
  }
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
  }

  final PageSnapshot page;
  try {
    page = await session.openAndRead(url, timeout: timeout);
  } on TimetableCaptureException {
    rethrow;
  } on TimeoutException {
    throw const TimetableCaptureException(CaptureErrorCode.networkTimeout);
  } catch (_) {
    // Do not expose platform exceptions: they can include URLs or tokens.
    throw const TimetableCaptureException(CaptureErrorCode.readFailed);
  }

  if (page.finalUrl.scheme != 'https' || page.finalUrl.host.isEmpty) {
    throw const TimetableCaptureException(CaptureErrorCode.unsupportedPage);
  }
  final TimetablePageKind kind;
  try {
    kind = classify(page);
  } catch (_) {
    throw const TimetableCaptureException(CaptureErrorCode.unsupportedPage);
  }
  return switch (kind) {
    TimetablePageKind.timetable => CapturedTimetablePage(
      text: page.text,
      mimeType: page.mimeType,
    ),
    TimetablePageKind.login => throw const TimetableCaptureException(
      CaptureErrorCode.loginExpired,
    ),
    TimetablePageKind.unsupported => throw const TimetableCaptureException(
      CaptureErrorCode.unsupportedPage,
    ),
  };
}
