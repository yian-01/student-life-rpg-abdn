# Issue #12 首批交付记录

负责人：郝文聪。记录日期：2026-10-11（Asia/Shanghai）。

## 材料和基线

- 仓库：`C:\Projects\student-life-rpg-abdn`。
- 分支：`feat/12-gpa-conflicts`，继续使用原有分支。
- HEAD、本地 main、fetch 后 origin/main：`aa64f1f41f9801b5882d6dd2b99837d795c0df4c`。
- 修改前 `git status --short` 为空；未 reset/clean，未改依赖或共享签名。
- 已读取 Issue #12 最新正文与全部 2 条评论（GitHub API），README、CONTRIBUTING、冻结契约 v1.0、平台规范、pubspec.yaml/lock、共享模型/仓库接口及现有测试。
- 采用统一契约 v1.0。用户已在会话提供完整《Student Life App：组员逐步开发手册》，已读取并按首批交付流程执行；工作区未找到 AGENTS.md。
- 初次核查 Issue 评论中未见郝文聪的开工反馈，发布结果以 GitHub 实际评论链接为准。
- 已核查 Git 提交身份和 GitHub 登录为 HAOSHUAI0516；GitHub API 返回共享仓库 permissions.push=false，阻塞推送和共享仓库 Draft PR。请组长检查该账号邀请/写权限；不 Fork 或修改 origin。

## 验收表

| 需求 | 实现与证据 | 状态 | 替身 |
| --- | --- | --- | --- |
| K 严格半开区间，相接不冲突 | `../schedule/services/conflict_detector.dart`；`test/conflict_detector_test.dart` | 已通过单测 | 无；使用正式共享类型 |
| K 包含、部分相交、空、单项 | 同上 | 已通过单测 | 无 |
| K 重复 ID 拒绝、每对一次、ID 确定排序 | 同上；重复 ID 抛 ArgumentError | 已通过单测 | 无 |
| K 原输入不变、跨日、微秒、所有来源参与 | 同上；返回不可变列表快照 | 已通过单测 | 无 |
| GpaResult 字段、不可变、0/null 区别 | `models/gpa_result.dart`；`test/gpa_result_test.dart` | 已通过单测；不代表 GPA 算法完成 | 无 |
| J 加权、合法性、溢出、重复课程 ID、输入不变 | `GpaCalculator` 尚未实现 | 阻塞：#10 正式 Course 未合并 | 未创建生产替身 |
| J Controller、学期筛选、成绩编辑、loading/error/retry | 尚未实现；GpaPage 保持现有占位 | 阻塞：正式 Course/Repository 缺失；页面接线需与 A 协调 | 无 |
| G/N 真实调用与组合根共享仓库 | academic 目录不存在；Dashboard 仅占位页面 | 未执行；依赖 #10/#14/A | 无 |
| Windows 页面运行与截图 | 本批没有页面改动 | 本次未执行；用户此前基线成功不算本次验证 | 不适用 |
| Android 原生运行 | doctor 未找到 Android SDK | 未执行 | 不适用 |
| 持久化与重启 | 本批纯算法和结果模型，不引入存储 | 不适用；不宣称 Course 持久化 | 不适用 |

## 实测检查

固定 SDK：Flutter 3.44.6 stable / Dart 3.12.2。
在 `frontend/` 顺序执行：

| 命令 | 退出码与结果 |
| --- | --- |
| `flutter pub get` | 0，依赖获取成功；pubspec/lock 无改动 |
| `dart format lib/features/schedule/services/conflict_detector.dart lib/features/gpa/models/gpa_result.dart test/conflict_detector_test.dart test/gpa_result_test.dart` | 0，4 文件，1 文件格式化 |
| `dart format --output=none --set-exit-if-changed lib test` | 0，20 文件，0 改动 |
| `flutter analyze` | 0，No issues found |
| `flutter test` | 0，26/26 通过；原有 15 + 新增 11 |

`flutter doctor -v` 退出 0，但报告 2 类问题：Android SDK 缺失、访问 maven.google.com 超时。Windows 与 Visual Studio 工具链通过；不把工具链通过当作原生启动通过。

## 精确调用示例

在 `frontend/` 内的 Dart 调用方使用：

```dart
import 'package:student_life_rpg/features/gpa/models/gpa_result.dart';
import 'package:student_life_rpg/features/schedule/services/conflict_detector.dart';
import 'package:student_life_rpg/shared/models/schedule_item.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

final courseRange = TimeRange(
  start: DateTime(2026, 10, 11, 9),
  end: DateTime(2026, 10, 11, 10),
);
final eventRange = TimeRange(
  start: DateTime(2026, 10, 11, 9, 30),
  end: DateTime(2026, 10, 11, 10, 30),
);
final conflicts = findConflicts([
  ScheduleItem(
    id: 'demo:course',
    sourceId: 'synthetic-course',
    sourceType: ScheduleSourceType.course,
    title: '合成课程演示',
    range: courseRange,
  ),
  ScheduleItem(
    id: 'demo:event',
    sourceId: 'synthetic-event',
    sourceType: ScheduleSourceType.event,
    title: '合成事件演示',
    range: eventRange,
  ),
]);
// conflicts.single: firstId='demo:course', secondId='demo:event'
// overlapRange=[2026-10-11 09:30, 2026-10-11 10:00)
// 以上是算法样例，不是正式课程或日程仓库接入证据。

const emptyGpa = GpaResult(
  value: null,
  gradedCredits: 0,
  gradedCourseCount: 0,
  missingCount: 0,
);
// 仅示范结果构造；GPA 计算器尚未交付。
```

I/A 应将真实日程 items 直接传给 `findConflicts(items)`，捕获非法重复 ID，不能按 sourceId 去重或截短跨日源 range。与 #9 共享 schedule/services 目录，但本批只新增本人负责的 conflict_detector.dart。N 应导入上述 GpaResult；正式 GPA 回调待 #10 的 Course 和 J 算法/Controller 交付后再接线。

## 待补材料与后续交付

1. 组长核查 HAOSHUAI0516 的共享仓库邀请/写权限；恢复后推送本人功能分支并创建 Draft PR。
2. #10 提供已合并的正式 Course 文件、构造器和 EntityRepository<Course> 实现；确认对应 PR 链接和 main SHA。
3. 本人在同一分支实现 GpaCalculator、GpaController、测试，并与 A 协调最小 GPA 页面和真实仓库接线。
4. #14/A 同步 main 后完成真实调用；补 Windows 运行截图和 Android 独立状态。
5. 首批在本地提交；有写权限后推送并开 Draft PR，由陈思翰审核，不自行合并或关闭 Issue。

## 开工反馈草稿（未发布）

郝文聪：采用统一契约 v1.0。实际 main SHA 为 aa64f1f41f9801b5882d6dd2b99837d795c0df4c；Flutter 3.44.6 stable / Dart 3.12.2。Windows/Visual Studio 工具链通过；Android SDK 未安装。pub get、格式检查、analyze 均退出 0；本批全量测试 26/26 通过（原有 15 + 新增 11）。Windows 原生运行本次未执行，用户此前基线已运行成功；Android 未执行。K 和 GpaResult 首批完成，J 真实接入受 #10 Course/Repository 缺失阻塞。手册已读取；GitHub API 返回 HAOSHUAI0516 对共享仓库 push=false，尚未推送或创建 PR，请组长核查邀请/写权限。

## 首批 PR 草稿（未创建）

标题：`feat(schedule): add deterministic conflict detection and GPA result (#12)`

关联 #12（部分交付，不关闭 Issue）。实现基于正式 TimeRange/ScheduleItem 的半开区间冲突检测，重复 ID 拒绝、唯一配对、确定排序及完整交集；新增共享不可变 GpaResult。没有修改页面、依赖或公共签名。

验证：Flutter 3.44.6 / Dart 3.12.2；pub get、格式检查、analyze、test 均退出 0；26 测试通过（保留 15，新增 11）。Windows/Android 本次原生运行未执行。

后续依赖：#10 正式 Course/Repository、#14/A 真实消费与页面接线；目前不能宣称 GPA 算法、Controller、页面或 G/N 联调完成。请求陈思翰审核本批独立算法；与 #9 协调冲突文件消费。

建议提交信息：`feat(schedule): add conflict detection and shared GPA result`
