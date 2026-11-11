import '../../timetable_capture/scnu_web_session.dart';
import '../../timetable_capture/timetable_page_capture.dart';
import 'scnu_html_preview.dart';
import 'timetable_import.dart';
import 'timetable_source.dart';

class ScnuTimetableHtmlLoader implements TimetableHtmlLoader {
  const ScnuTimetableHtmlLoader(this.session);

  final AuthenticatedPageSession session;

  @override
  Future<String> load(
    Uri url, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!isScnuTimetableUrl(url)) {
      throw const TimetableLoadException(
        TimetableLoadError.invalidUrl,
        detail: '请输入 jwxt.scnu.edu.cn 的 HTTPS 课表网址。',
      );
    }
    try {
      final captured = await captureTimetablePage(
        url: url,
        session: session,
        classify: classifyScnuTimetablePage,
        timeout: timeout,
      );
      return captured.text;
    } on TimetableCaptureException catch (error) {
      throw TimetableLoadException(TimetableLoadError.values.byName(error.code.name));
    }
  }
}

TimetablePageKind classifyScnuTimetablePage(PageSnapshot page) {
  if (!isScnuBrowserUrl(page.finalUrl)) return TimetablePageKind.unsupported;
  if (isScnuTimetableUrl(page.finalUrl) &&
      page.mimeType == 'text/html' &&
      RegExp(r'''<table\b[^>]*\bid=["']kbgrid_table_0["']''',
        caseSensitive: false,
      ).hasMatch(page.text)) {
    return TimetablePageKind.timetable;
  }
  if (RegExp(r'''type=["']password["']''', caseSensitive: false).hasMatch(page.text)) {
    return TimetablePageKind.login;
  }
  return TimetablePageKind.unsupported;
}

class ScnuTimetableHtmlParser implements TimetableHtmlParser {
  const ScnuTimetableHtmlParser();

  @override
  TimetableParseResult parse(String html, {int? maxWeek}) {
    if (maxWeek == null || maxWeek < 1) {
      throw const FormatException('所选学期没有可导入的上课周次。');
    }
    return parseScnuHtml(html, maxWeek: maxWeek);
  }
}
