import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/timetable_capture/timetable_page_capture.dart';

class FakeSession implements AuthenticatedPageSession {
  FakeSession(this.read);

  final Future<PageSnapshot> Function(Uri, Duration) read;

  @override
  Future<PageSnapshot> openAndRead(Uri url, {required Duration timeout}) =>
      read(url, timeout);
}

void main() {
  final timetableUrl = Uri.parse('https://example.edu/timetable');
  const pageText = '<table><tr><td>示例课程</td></tr></table>';
  final timetablePage = PageSnapshot(
    finalUrl: timetableUrl,
    text: pageText,
    mimeType: 'text/html',
  );

  test(
    'uses the supplied session and returns only classified page content',
    () async {
      Uri? loadedUrl;
      Duration? receivedTimeout;
      final result = await captureTimetablePage(
        url: timetableUrl,
        session: FakeSession((url, timeout) async {
          loadedUrl = url;
          receivedTimeout = timeout;
          return timetablePage;
        }),
        classify: (_) => TimetablePageKind.timetable,
        timeout: const Duration(seconds: 9),
      );
      expect(loadedUrl, timetableUrl);
      expect(receivedTimeout, const Duration(seconds: 9));
      expect(result.text, pageText);
      expect(result.mimeType, 'text/html');
    },
  );

  for (final (kind, code) in [
    (TimetablePageKind.login, CaptureErrorCode.loginExpired),
    (TimetablePageKind.unsupported, CaptureErrorCode.unsupportedPage),
  ]) {
    test('$kind maps to $code without returning page content', () async {
      await expectLater(
        captureTimetablePage(
          url: timetableUrl,
          session: FakeSession((_, _) async => timetablePage),
          classify: (_) => kind,
        ),
        throwsA(
          isA<TimetableCaptureException>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    });
  }

  test('timeout and host errors have separate safe result codes', () async {
    for (final (failure, code) in [
      (TimeoutException('network request'), CaptureErrorCode.networkTimeout),
      (
        const TimetableCaptureException(CaptureErrorCode.networkUnavailable),
        CaptureErrorCode.networkUnavailable,
      ),
      (StateError('private platform details'), CaptureErrorCode.readFailed),
    ]) {
      try {
        await captureTimetablePage(
          url: timetableUrl,
          session: FakeSession((_, _) => Future.error(failure)),
          classify: (_) => TimetablePageKind.timetable,
        );
        fail('Expected a capture error.');
      } on TimetableCaptureException catch (error) {
        expect(error.code, code);
        expect(error.toString(), isNot(contains('private platform details')));
      }
    }
  });

  test('rejects insecure URL before loading the browser session', () async {
    var loads = 0;
    await expectLater(
      captureTimetablePage(
        url: Uri.parse('http://example.edu/timetable'),
        session: FakeSession((_, _) async {
          loads++;
          return timetablePage;
        }),
        classify: (_) => TimetablePageKind.timetable,
      ),
      throwsA(
        isA<TimetableCaptureException>().having(
          (error) => error.code,
          'code',
          CaptureErrorCode.invalidUrl,
        ),
      ),
    );
    expect(loads, 0);
  });

  test('classifier failure cannot leak page text through the error', () async {
    try {
      await captureTimetablePage(
        url: timetableUrl,
        session: FakeSession((_, _) async => timetablePage),
        classify: (_) => throw StateError('private page details'),
      );
      fail('Expected an unsupported page error.');
    } on TimetableCaptureException catch (error) {
      expect(error.code, CaptureErrorCode.unsupportedPage);
      expect(error.toString(), isNot(contains('private page details')));
    }
  });
}
