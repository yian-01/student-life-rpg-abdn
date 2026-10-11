# Issue #10 学术模块交付记录

关联：[Issue #10](https://github.com/yian-01/student-life-rpg-abdn/issues/10)。负责人：蒋子康。采用统一契约 v1.0。

日期：2026-10-11（Asia/Shanghai）。工作目录：`C:\Projects\student-life-rpg-fresh`。
分支：`feat/10-academic-occurrences`。原开发基线：`aa64f1f41f9801b5882d6dd2b99837d795c0df4c`；PR 创建后已合入最新 main `69123b8cfd85ab7e2c014fdcce116db12d8d84e8`。
上列 SHA 为开发基线。本轮实现的实际提交 SHA 与 PR 链接以 Git 历史和 GitHub PR 为准；用户已明确授权提交、推送和创建 PR。

## 来源与迁移

已读取用户两个相同附件的完整原文、README、CONTRIBUTING、冻结契约全部章节、pubspec.yaml/lock、正式共享类型和基线测试。未发现 AGENTS.md。
已直接核对 Issue 正文及页面展示的全部两条评论（固定 SDK 通知和开工 Prompt）。网页渲染会丢失部分尖括号，泛型与 ID 以本地原始契约 Markdown 为准。

旧目录 `C:\Projects\student-life-rpg-abdn` 的 `af54c8306ea7b97d85d1827027dd7e37d427939c` 是包含工程全树的根提交，无父提交，不能按普通功能提交 cherry-pick。
仅迁入 `frontend/lib/features/academic/`、`frontend/test/academic/`，目标路径原先不存在；旧目录及其未跟踪 ZIP 均保留。
复用迁移的 59 项学术测试，新增 8 项回归测试；原有 15 项共享/Widget 测试和公共类型、SDK/依赖清单未改动。

迁移后修复：评分制必须显式传入；引用回调必须显式注入；异步检查返回后重新校验重复插入和未知更新；周次使用 Gregorian 日历序号差；分钟端点使用民用时间构造；UTC 查询拒绝；日期字段年份必须能按 YYYY-MM-DD 往返。

本轮 fetch 曾因 TLS 握手失败；随后 `git ls-remote origin refs/heads/main` 成功，确认在线 main 仍是上述 SHA。没有关闭证书验证或修改全局 Git 配置。

## 验收结果

| 要求 | 实现 | 证据 | 状态 / 替身 |
| --- | --- | --- | --- |
| 五种学术模型及 CourseSlot 不可变、JSON 往返、未知键拒绝 | `models/semester.dart`、`course.dart`、`course_slot.dart`、`assignment.dart`、`exam.dart` | `academic_models_test.dart`、`assignment_exam_test.dart`、回归 wire JSON 测试 | 通过；正式模型 |
| 可空字段写出 null、缺可空键按 null；非法日期及领域值为 FormatException | `academic_json.dart`、`local_date.dart` 及各模型解码器 | 模型/作业/考试测试 | 通过；正式解码 |
| 本地午夜、学期含首尾、周一锚点、非有限 credits/gradePoint 拒绝 | 模型构造器 | 模型测试、回归首尾/锚点/年份测试 | 通过 |
| CRUD、重复/未知更新、未知查询/删除、ID 保留、不可变快照 | 两个内存 Repository | `academic_repository_test.dart`、回归快照/并发重复插入 | 通过；独立 CRUD 测试部分使用显式回调替身 |
| 课程必须引用已有学期、有课程时禁止删除学期 | 两仓库的必填回调 | 原引用保护测试及新增真实配对测试 | 通过；真实两仓库互相查询，无替身 |
| 数学 10-05 有 / 10-12 无 / 10-19 有；英语 10-07、10-14 有 | `services/course_occurrence_service.dart` | `course_occurrence_test.dart`；可执行样例输出相同 | 通过；标注合成数据 |
| 学期外、星期错、未生效周次为空；学期 ID 不符拒绝 | `occurrencesForDate` | 课次测试与回归测试 | 通过 |
| 0 与 1440、本地半开区间、稳定编码 ID、多 slot 不碰撞、不修改输入 | 同上 | 课次测试 | 通过 |
| 日历差跨闰日、月、年；UTC 查询拒绝 | 同上 | `academic_regression_test.dart` | 通过；未执行更改操作系统时区后的 DST 原生检查 |
| I 异步回调样例与 J 的正式 Course 输入 | `example/academic_occurrences.dart` | `dart run example/academic_occurrences.dart` 退出 0 | 本模块真实仓库链路通过；I/J 服务联调未执行 |
| Windows / Android 原生 UI | 本 Issue 无新增 UI | 未运行 flutter run，无截图/录屏 | 未执行 |
| 提交、推送、PR、合并后消费方验证 | 等待用户确认后进行前三项；组长审核合并 | 无 PR / Actions 链接 | 未执行 |

## 已执行命令

Flutter 3.44.6 stable，Dart 3.12.2，Windows x64。此前遥测文件不可写，验证命令仅将当前进程的 APPDATA 指向临时工具目录，设置 CI / suppress analytics；没有修改用户原遥测文件、SDK 或项目依赖版本。

| 命令（在 frontend 中） | 结果 |
| --- | --- |
| `flutter pub get` | 退出 0；Got dependencies；lock 无变化 |
| `dart format lib/features/academic test/academic example` | 已格式化本人文件 |
| `dart format --output=none --set-exit-if-changed lib test` | 退出 0；32 files，0 changed |
| `flutter analyze` | 退出 0；No issues found |
| `flutter test --reporter expanded` | 退出 0；82 项通过 = 原有 15 + 学术 67 |
| `dart run example/academic_occurrences.dart` | 退出 0；日期计数 1 / 0 / 1 / 1 / 1，J 输入 math:3.7、english:null |

曾因命令行样例使用 print 触发 avoid_print，已改用 dart:io 的 stdout.writeln；最终检查全部通过，未关闭 lint。

## 精确导入与构造

```dart
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/course_slot.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/models/exam.dart';
import 'package:student_life_rpg/features/academic/repositories/semester_repository.dart';
import 'package:student_life_rpg/features/academic/repositories/course_repository.dart';
import 'package:student_life_rpg/features/academic/services/course_occurrence_service.dart';
```

```dart
late final InMemoryCourseRepository courses;
final semesters = InMemorySemesterRepository(
  isReferenced: (id) => courses.hasCoursesForSemester(id),
);
courses = InMemoryCourseRepository(semesterExists: semesters.exists);
// 先构造完成配对，再使用仓库；禁止注入恒 true/false 的生产回调。

final semester = Semester(
  id: 's', name: '合成学期',
  startDate: DateTime(2026, 10, 5), endDate: DateTime(2027, 1, 24),
  week1Monday: DateTime(2026, 10, 5),
);
await semesters.insert(semester);
final course = Course(
  id: 'math', semesterId: 's', name: '数学（合成数据）', credits: 5,
  gradePoint: 3.7, scoreScaleMax: 4.0,
  slots: [CourseSlot(weekday: 1, startMinute: 480, endMinute: 580, weeks: [1, 3, 5])],
);
await courses.insert(course);
final restored = Course.fromJson(course.toJson(), scoreScaleMax: 4.0);
final items = occurrencesForDate(restored, semester, DateTime(2026, 10, 5));
// items.single.id == 'course:math:0:20261005'
```

`Course` 的 `slots` 和 `scoreScaleMax` 为 required；`gradePoint` 可省略/null。
`scoreScaleMax` 为构造/解码参数，不加入冻结实体字段，也不写入 JSON。创建或更新课程的引用校验在仓库执行，模型构造不执行 IO。
其余模型非空字段为 required 命名参数；Assignment.description、Exam.location 可省略/null。
Repository 复用正式 `EntityRepository<T>`；模型无可修改 ID 的 copyWith。

完整可运行样例位于 `frontend/example/academic_occurrences.dart`。其中 `loadCourseOccurrences` 闭包的签名是 `Future<List<ScheduleItem>> Function(DateTime)`，供 A/I 注入 `DayScheduleService.courseOccurrencesForDate`；这不是新增生产聚合服务。
J 通过 `await courses.listForSemester(semesterId)` 获取同一 `List<Course>`，在 #12 合并后传入 `GpaCalculator.calculate(..., scoreScaleMax: 4.0)`。
本分支不复制 DayScheduleService 或 GpaCalculator，不以样例代替消费方正式联调。

## 依赖和限制

- PR #4、#5、#6 已在基础 main 合并，正式共享依赖已满足。
- #9 日程、#12 GPA 和 #15 组合接线的实际消费方联调需在 G 合并后由消费方同步 main 验证。
- 学期/课程均为内存数据，重启不保留；Assignment/Exam 仅模型与 JSON，不含管理页面或仓库。
- 4.0 及数学单周/英语每周均为合成演示规则，不代表学校正式评分政策。
- 两仓库通过注入回调协作，没有跨仓库事务；组合根应顺序 await 引用相关变更，不并发执行学期删除与课程插入/换学期。
- 生产源码使用正式共享类型；隔离仓库单测有显式 true/false 回调，真实配对测试及样例不使用替身。
- Windows/Android 原生运行、跨时区 DST 环境、PR Actions 和合并后 I/J 联调未执行，不列为通过。

## 提交文件（20 个，含 CI 整改）

```text
docs/development/issue-10-academic-handoff.md
frontend/example/academic_occurrences.dart
frontend/example/academic_synthetic_data.dart
frontend/lib/features/academic/models/academic_json.dart
frontend/lib/features/academic/models/assignment.dart
frontend/lib/features/academic/models/course.dart
frontend/lib/features/academic/models/course_slot.dart
frontend/lib/features/academic/models/exam.dart
frontend/lib/features/academic/models/local_date.dart
frontend/lib/features/academic/models/semester.dart
frontend/lib/features/academic/repositories/course_repository.dart
frontend/lib/features/academic/repositories/semester_repository.dart
frontend/lib/features/academic/services/course_occurrence_service.dart
frontend/test/academic/academic_models_test.dart
frontend/test/academic/academic_regression_test.dart
frontend/test/academic/academic_repository_test.dart
frontend/test/academic/assignment_exam_test.dart
frontend/test/academic/course_occurrence_test.dart
frontend/test/academic/fixtures.dart
```

## 提交动作与 PR 正文

用户确认后仅暂存上列 19 个文件，以 `feat: implement academic models repositories and occurrences (#10)` 提交，推送 `origin/feat/10-academic-occurrences`，以 main 为 base 创建 PR。不会自动合并或关闭 Issue。

建议标题：`[#10] 学术模型、内存仓库与课次展开`。

建议正文：

> Refs #10。新增不可变 Semester/Course/CourseSlot/Assignment/Exam、严格 JSON 校验、Semester/Course 内存仓库和单课程课次展开。引用检查显式注入，评分上限由调用方提供；派生 ID 保留 slotIndex，周次使用日历差。
>
> 包含标注合成数据的可运行 A/I 异步适配样例及 J Course 输入。依赖 PR #4/#5/#6 已合并。完整验收、精确导入、调用方式和限制见 docs/development/issue-10-academic-handoff.md。
>
> Flutter 3.44.6 / Dart 3.12.2；pub get、格式检查、analyze、82 项测试与调用样例通过；保留原有 15 项测试。Windows/Android 原生 UI、Actions、合并后 I/J 联调未执行。内存数据重启不保留。请陈思翰审核。

PR 正文记录本轮新提交的真实 SHA；不会在本文件中使用自引用提交 SHA。

## PR #22 的 CI 整改

PR：https://github.com/yian-01/student-life-rpg-abdn/pull/22 。首个提交为 5baabaea9ce8056788aba0b4a56ea743273a57e9。

创建 PR 后远程 main 新增了 .github/workflows/dart.yml（69123b8）。首次 Actions 38144839131 失败在 Install dependencies：Expected to find project root in current working directory；分析与测试被跳过。日志还显示未固定 stable 实际安装 Flutter 3.47.7。

已在本功能分支合入该 main 并修正 CI：所有 run 步骤统一在 frontend 执行，Flutter 固定 3.44.6 stable，并补充契约要求的格式检查。保留完整分析与测试。除原 19 个文件外，本 PR 增加该工作流修正，合计 20 个文件。整改后的实际 Actions 链接和结果以 PR 正文为准，不将首次失败记为通过。
