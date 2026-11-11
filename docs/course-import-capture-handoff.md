# Issue #37 → #34 / #31 / #30：教务课表采集交接草案

状态：**待三方确认的接口草案**，不是已登录的学校页面或可运行的导入功能。
基线：`fix/v1-interaction-followup`，关联 #37、#34、#31、#30、#58。
负责人：#37 采集与返回焦点；#34 解析；#31 预览与领域映射；#30 批量事务保存。

## 当前已实现的纯 Dart 接口

文件：`frontend/lib/features/timetable_capture/timetable_page_capture.dart`。此层已可编译、可单测；它不创建浏览器，也不读取系统浏览器的 Cookie。当前没有 `AuthenticatedPageSession` 的 Android/Windows 实现，因此**尚不能对真实学校网址抓取带登录态的页面**。

```dart
Future<CapturedTimetablePage> captureTimetablePage({
  required Uri url,
  required AuthenticatedPageSession session,
  required TimetablePageClassifier classify,
  Duration timeout = const Duration(seconds: 20),
});
```

调用形式（`session` 必须是用户在同一 App 内完成登录的网页宿主；`classify` 由真实来源适配器提供）：

```dart
try {
  final page = await captureTimetablePage(
    url: timetableUrl,
    session: authenticatedSession,
    classify: timetableClassifier,
  );
  final draft = parser.parse(page.text); // #34 的实际 API 待确认
} on TimetableCaptureException catch (error) {
  switch (error.code) {
    case CaptureErrorCode.loginExpired: /* 重新登录 */ break;
    case CaptureErrorCode.networkTimeout: /* 重试 */ break;
    case CaptureErrorCode.unsupportedPage: /* 不支持页 */ break;
    default: /* 取消、断网或读取失败 */ break;
  }
}
```

上例 `parser.parse` 是衔接位置的示意，**不是仓库中现有的可调用函数**。接口当前还包含 `cancelled`、`networkUnavailable`、`readFailed`、`invalidUrl` 错误码。宿主需在超时时停止底层导航并抛 `TimeoutException`；会话失效或用户取消可直接抛对应的 `TimetableCaptureException`。最终页面经 `classify` 判为 `login` 时转成 `loginExpired`，判为 `unsupported` 时转成 `unsupportedPage`。底层异常的文本不会向上返回，以免 URL、页面内容或令牌泄露。真实页面分类规则须由 #34 与 #37 用脱敏样例确认。

## 1. 流程与边界

`App 内网址导入 → 用户在学校页面自行登录 → 识别当前个人课表页 → #37 采集 → #34 解析成草稿 → #31 预览/补字段/确认 → #30 一次事务保存 → 日程读取`。

- #37 仅采集当前课表所需页面内容，不解析课程、不写 `CampusStore` 或 `TaskRepository`。采集结果只在本次导入流程内存中传递；取消即丢弃。
- #34 收到采集结果后先识别登录页、错误页、空课表、不支持格式，再解析课程、周次、单双周、星期、节次/时刻和地点；不能把登录页解析成“0 门课成功”。
- #31 将草稿映射到当前学期，显示新增、变更、重复和缺失字段，允许修正；学分缺失由用户补齐，`gradePoint` 保持 `null`，预览/取消不写盘。
- #30 在同一 `campus.json` 事务中校验来源身份、引用和冲突，批量提交；任一校验或写入失败时不得留下半批课程，不跨写 `tasks.json`。
- 应用路由由组长接线；网页宿主和新依赖/平台配置需组长核定版本。#37 负责关闭认证/导入页后房间输入和焦点回归。

## 2. 建议的采集结果（#37 → #34）

以下字段名是**提议**，须由 #34 确认后再固化为 Dart 接口：

| 字段 | 含义与约束 |
| --- | --- |
| `provider` | 来源适配器标识；暂用 `scnu-jwxt` 作为候选，须由实际个人课表页面确认。 |
| `capturedAt` | ISO 8601 时间，用于诊断过期内容；不参与课程身份。 |
| `pageKind` | `timetable` 才可交解析器；`login`、`error`、`unknown` 直接返回对应错误。 |
| `semesterHint` | 页面能明确读到时才提供原文标签；为空时由 #31 让用户选择学期，不推断学期日期。 |
| `parts[]` | 一个或多个课表内容片段，支持顶层 HTML、iframe HTML 或课表异步响应。按页面实际来源采集；不抓取无关请求。 |
| `parts[].surface` | `document`、`iframe` 或 `response`。 |
| `parts[].mimeType` | 例如 `text/html` 或 `application/json`。 |
| `parts[].sourcePath` | 仅保留不含查询参数、身份标识和令牌的来源路径；实际 URL 只在内存中用于页面导航。 |
| `parts[].body` | 原始课表片段，仅在本次导入内存传递。生产环境不得写入日志、报告或公开 fixture。 |

**合成格式示例（不是学校真实页面）：**

```json
{
  "provider": "scnu-jwxt",
  "capturedAt": "2026-11-06T10:00:00+08:00",
  "pageKind": "timetable",
  "semesterHint": "示例学期",
  "parts": [
    {
      "surface": "document",
      "mimeType": "text/html",
      "sourcePath": "/example/timetable",
      "body": "<table><tr data-course-id='SYNTHETIC-001'><td>示例课程</td><td>周一</td><td>第1-3周</td><td>08:00-09:40</td><td>示例教室</td></tr></table>"
    }
  ]
}
```

`SYNTHETIC-001`、路径和课程均为虚构测试值，不证明华师真实课表含这些字段。实际页面可能由 iframe 或异步请求生成，取得脱敏样例后须据此调整 `parts` 结构。不得为了匹配此示例去猜测学校页面字段。

## 3. #34 → #31 → #30 的必要字段

#34 输出**预览草稿**，而非直接构造可保存的 `Course`。每门草稿至少需：来源课程身份（若页面有）、课程名、每组上课时段的星期/周次/单双周/节次及可确定的实际时刻、地点和页面可用的教师字段；缺失字段及解析警告单列。不能仅凭课程名去重；同名不同课必须可区分。页面不给学分时标记“待补”，不得填 1；页面不给成绩时不得自行换算。

#31 确认后才映射当前模型：`Course(id, semesterId, name, credits, gradePoint, slots)`；`CourseSlot(weekday, startMinute, endMinute, weeks)`。`weekday` 为周一 1 至周日 7，分钟为本地当天 00:00 起算且 `0 ≤ startMinute < endMinute ≤ 1440`，`weeks` 为严格递增的正整数。`Semester` 使用 `week1Monday` 作为周次锚点，并校验首尾日期与部分周。来源身份及人工修改冲突策略需 #30 确认是否扩展受支持 schema，不能把未定义来源字段塞入现有 `Course` JSON（其解码拒绝未知键）。

#30 接收经 #31 确认的批次及来源身份/变更计划，负责原子保存、重复导入、存储故障和进程重开验证。预览阶段和认证取消均不得调用保存。

## 4. 错误归属与用户反馈

| 位置 | 状态 | 期望行为 |
| --- | --- | --- |
| 网页宿主 / #37 | 用户取消认证、登录过期、网络超时、校园网不可达 | 保持原数据；显示明确原因，允许返回或重试。不得把密码、Cookie 或令牌交解析器。 |
| #37 → #34 边界 | 尚在登录页、抓不到当前课表片段、页面来源不明 | 不提交解析成功；记录可脱敏诊断信息，返回“不支持/未取得课表”。 |
| #34 | 空课表、格式不支持、缺字段、无效周次/节次 | 返回可区分的解析结果和字段问题；不伪装成 0 门成功。 |
| #31 | 学期不明确、缺学分、与人工记录冲突 | 留在预览供用户修正/选择；取消不写盘。 |
| #30 | 重复导入、校验或写入失败 | 显示批次结果；失败无半批数据，已有成绩及无关数据不受影响。 |

## 5. 真实脱敏样例的补交条件

目前尚未取得用户授权登录后的实际个人课表，**因此没有真实可回放样例**。采集时需由用户本人在学校页面登录，先核对页面是否确为目标来源，再提供：

1. 去身份化的页面/响应片段及其 `surface`、`mimeType`、无敏感参数的来源路径；若 iframe/异步响应参与渲染，保留足以重放的关联片段。
2. 人工核对表：课程数、每门课的周次/单双周、星期、节次对应时间与地点；记录页面未给出的字段。
3. 一份登录页或错误页的脱敏反例，用于验证解析器拒绝假成功。
4. 平台、应用 SHA、网页宿主版本和测试日期；个人姓名、学号、密码、Cookie、令牌及敏感 URL 不进入 fixture、截图、日志或报告。

需 #34 确认 `parts` 输入，#31 确认草稿与缺字段交互，#30 确认来源身份及批量事务接口；确认后再把此草案改成编译期契约。Windows/Android 原生登录与回归仍须在可用设备上实际执行。
