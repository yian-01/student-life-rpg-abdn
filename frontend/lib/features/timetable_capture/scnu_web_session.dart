import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'timetable_page_capture.dart';

const scnuTimetableHost = 'jwxt.scnu.edu.cn';

bool isScnuBrowserUrl(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    (uri.host == 'scnu.edu.cn' || uri.host.endsWith('.scnu.edu.cn'));

bool isScnuTimetableUrl(Uri uri) =>
    isScnuBrowserUrl(uri) && uri.host == scnuTimetableHost;

class ScnuWebSession implements AuthenticatedPageSession {
  const ScnuWebSession(this.context);

  final BuildContext context;

  @override
  Future<PageSnapshot> openAndRead(Uri url, {required Duration timeout}) async {
    if (!isScnuTimetableUrl(url)) {
      throw const TimetableCaptureException(CaptureErrorCode.invalidUrl);
    }
    final supported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.windows);
    if (!supported) {
      throw const TimetableCaptureException(CaptureErrorCode.readFailed);
    }
    final page = await Navigator.of(context).push<PageSnapshot>(
      MaterialPageRoute(
        builder: (_) => _ScnuBrowser(url: url, timeout: timeout),
      ),
    );
    if (page == null) {
      throw const TimetableCaptureException(CaptureErrorCode.cancelled);
    }
    return page;
  }
}

// Only the schedule table and the presence of an unscheduled section leave
// the browser. Same-origin frames may contain the actual rendered timetable.
const _readGrid = r'''
(() => {
  if (window.location.origin !== 'https://jwxt.scnu.edu.cn') return '';
  function read(frame, depth) {
    if (depth > 4) return null;
    try {
      if (frame.location.origin !== window.location.origin) return null;
      const doc = frame.document;
      const table = doc.getElementById('kbgrid_table_0');
      if (table && table.tagName === 'TABLE') {
        const other = /其它课程|其他课程/.test(doc.body?.innerText ?? '');
        return table.outerHTML + (other ? '<p>其它课程</p>' : '');
      }
      for (let i = 0; i < frame.length; i++) {
        const result = read(frame.frames[i], depth + 1);
        if (result) return result;
      }
    } catch (_) {
      // Cross-origin frames are never read.
    }
    return null;
  }
  return JSON.stringify({
    grid: read(window, 0),
    login: Boolean(document.querySelector('input[type="password"]'))
  });
})()
''';

class _ScnuBrowser extends StatefulWidget {
  const _ScnuBrowser({required this.url, required this.timeout});

  final Uri url;
  final Duration timeout;

  @override
  State<_ScnuBrowser> createState() => _ScnuBrowserState();
}

class _ScnuBrowserState extends State<_ScnuBrowser> {
  InAppWebViewController? _controller;
  bool _loading = true;
  bool _reading = false;
  String? _error;
  late final Future<WebViewEnvironment?> _environment = _openEnvironment();

  Future<WebViewEnvironment?> _openEnvironment() async {
    if (defaultTargetPlatform != TargetPlatform.windows) return null;
    if (await WebViewEnvironment.getAvailableVersion() == null) {
      throw StateError('WebView2 Runtime unavailable');
    }
    final support = await getApplicationSupportDirectory();
    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: '${support.path}\\scnu-webview',
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_disposeEnvironment());
    super.dispose();
  }

  Future<void> _disposeEnvironment() async {
    try {
      final environment = await _environment;
      await environment?.dispose();
    } catch (_) {
      // Runtime setup may already have failed.
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _reading || _loading) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final url = Uri.tryParse(
        (await controller.getUrl().timeout(widget.timeout))?.toString() ?? '',
      );
      if (!mounted) return;
      if (url == null || !isScnuTimetableUrl(url)) {
        setState(() => _error = '请在学校页面登录，并打开个人课表后再读取。');
        return;
      }
      final value = await controller
          .evaluateJavascript(source: _readGrid)
          .timeout(widget.timeout);
      if (!mounted) return;
      final result = value is String && value.isNotEmpty
          ? jsonDecode(value)
          : value;
      final grid = result is Map ? result['grid'] : null;
      if (grid is! String || grid.isEmpty) {
        setState(() {
          _error = result is Map && result['login'] == true
              ? '当前仍是登录页，请登录后打开个人课表。'
              : '未找到支持的课表。请打开个人课表，等待内容加载后重试。';
        });
        return;
      }
      Navigator.of(
        context,
      ).pop(PageSnapshot(finalUrl: url, text: grid, mimeType: 'text/html'));
    } on TimeoutException {
      unawaited(_stopLoading(controller));
      if (mounted) setState(() => _error = '读取课表超时，请重试。');
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取当前页面，请重试。');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _stopLoading(InAppWebViewController controller) async {
    try {
      await controller.stopLoading();
    } catch (_) {
      // The platform view may already have been closed.
    }
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _error = null);
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(widget.url.toString())),
      );
    } catch (_) {
      if (mounted) setState(() => _error = '无法重新打开网址，请返回后重试。');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('华师个人课表'),
      actions: [
        IconButton(
          tooltip: '重新打开课表网址',
          onPressed: _controller == null || _reading ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<WebViewEnvironment?>(
      future: _environment,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('需要 Microsoft Edge WebView2 Runtime。安装后重试，或返回粘贴课表文本。'),
          );
        }
        return Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(padding: const EdgeInsets.all(8), child: Text(error)),
            Expanded(
              child: InAppWebView(
                webViewEnvironment: snapshot.data,
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.url.toString()),
                ),
                initialSettings: InAppWebViewSettings(
                  useShouldOverrideUrlLoading: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  supportMultipleWindows: false,
                  allowFileAccess: false,
                  allowContentAccess: false,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                ),
                onWebViewCreated: (controller) {
                  if (mounted) setState(() => _controller = controller);
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  if (action.isForMainFrame == false) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  final uri = Uri.tryParse(action.request.url.toString());
                  if (uri != null && isScnuBrowserUrl(uri)) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  if (mounted) {
                    setState(() {
                      _error = '已阻止跳转到非学校网址。请核对链接后重试。';
                      _loading = false;
                    });
                  }
                  return NavigationActionPolicy.CANCEL;
                },
                onLoadStart: (controller, url) {
                  if (!mounted) return;
                  final uri = Uri.tryParse(url?.toString() ?? '');
                  if (uri != null && isScnuBrowserUrl(uri)) {
                    setState(() => _loading = true);
                  } else {
                    unawaited(_stopLoading(controller));
                    setState(() {
                      _loading = false;
                      _error = '已阻止打开非学校网址。';
                    });
                  }
                },
                onLoadStop: (_, _) {
                  if (mounted) setState(() => _loading = false);
                },
                onReceivedError: (_, request, _) {
                  if (mounted && request.isForMainFrame == true) {
                    setState(() {
                      _loading = false;
                      _error = '页面加载失败，请检查网络并重新打开课表网址。';
                    });
                  }
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: FilledButton(
                  onPressed: _controller == null || _loading || _reading
                      ? null
                      : _capture,
                  child: Text(_reading ? '正在读取…' : '读取当前课表'),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
