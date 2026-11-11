import '../services/timetable_import.dart';

/// 抓取层端口：给定课表页网址，返回页面 HTML/文本。
///
/// 真实实现由 #37（黎宇轩）提供：
/// `captureTimetablePage(url:, session:, classify:)` 返回 `CapturedTimetablePage.text`。
/// 本模块只依赖这个窄接口，不复制其实现，也不接触密码 / Cookie / 令牌。
///
/// 失败时必须抛出 [TimetableLoadException]，用 [TimetableLoadError] 表达原因，
/// 这样界面可以按错误码给出可理解提示（AC10），而不是把原始异常文本甩给用户。
abstract interface class TimetableHtmlLoader {
  Future<String> load(Uri url, {Duration timeout});
}

/// 解析层端口：把页面 HTML/文本解析成 [TimetableParseResult]。
///
/// 真实实现由 #34（郝文聪）提供（`ScnuTimetableReader`），
/// 输出结构就是我们既有的 `TimetableParseResult / ParsedCourse / ParsedSlot`。
abstract interface class TimetableHtmlParser {
  TimetableParseResult parse(String html, {int? maxWeek});
}

/// 抓取失败的稳定错误码，与 #37 的 `CaptureErrorCode` 一一对应。
enum TimetableLoadError {
  loginExpired,
  networkTimeout,
  unsupportedPage,
  cancelled,
  networkUnavailable,
  readFailed,
  invalidUrl,

  /// 抓取层尚未接线（本仓库在 #37 合入前处于该状态）。
  notWired,
}

class TimetableLoadException implements Exception {
  const TimetableLoadException(this.error, {this.detail});

  final TimetableLoadError error;

  /// 额外的可读说明；**不得包含 URL、Cookie、令牌或页面内容**。
  final String? detail;

  @override
  String toString() => 'TimetableLoadException($error)';
}

/// 默认抓取实现：明确报告"尚未接线"。
///
/// 刻意不返回空字符串或假数据——否则界面会显示"0 门课程"，
/// 让人误以为导入成功（组长明确禁止"假成功"）。
class NotWiredTimetableHtmlLoader implements TimetableHtmlLoader {
  const NotWiredTimetableHtmlLoader();

  @override
  Future<String> load(
    Uri url, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    throw const TimetableLoadException(
      TimetableLoadError.notWired,
      detail: '抓取层（#37）尚未接入，当前请使用粘贴文本方式导入',
    );
  }
}

/// 默认解析实现：明确报告"尚未接线"。
class NotWiredTimetableHtmlParser implements TimetableHtmlParser {
  const NotWiredTimetableHtmlParser();

  @override
  TimetableParseResult parse(String html, {int? maxWeek}) {
    throw const FormatException('解析层（#34）尚未接入，无法把网页内容解析为课程');
  }
}

/// 把错误码翻译成用户能看懂的一句话（不含 URL、凭据或页面内容）。
String describeLoadError(TimetableLoadException error) {
  return switch (error.error) {
    TimetableLoadError.loginExpired => '登录已失效，请在学校页面重新登录后再试。',
    TimetableLoadError.networkTimeout => '加载超时，请检查网络后重试。',
    TimetableLoadError.unsupportedPage => '这不是受支持的课表页面，请确认打开的页面。',
    TimetableLoadError.cancelled => '已取消加载。',
    TimetableLoadError.networkUnavailable => '网络不可用，请检查连接后重试。',
    TimetableLoadError.readFailed => '读取页面失败，请重试。',
    TimetableLoadError.invalidUrl =>
      error.detail ?? '请输入有效的 HTTPS 课表页网址。',
    TimetableLoadError.notWired => error.detail ?? '抓取层尚未接入，当前请使用粘贴文本方式导入。',
  };
}

/// 校验用户输入的网址：必须是 HTTPS 且不带 userInfo（对齐 #37 的安全要求）。
Uri? parseTimetableUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'https') return null;
  if (uri.userInfo.isNotEmpty) return null;
  if (uri.host.isEmpty) return null;
  return uri;
}
