# Issue #12 GPA 与冲突交付

日期：2026-10-12（北京时间）。负责人：郝文聪。采用统一契约 v1.0。

开发基线：main `72dc639`。首批 PR #17 已审核合并，本批按手册从最新 main 创建 `feat/12-gpa-complete`；正式 G 模块来自已合并 PR #22。已重新核对 #12 正文、全部评论和 #17 审核，冻结契约未变。未升级 SDK/依赖，未复制生产 Course 或共享类型。

## 实现和验收

| 需求 | 实际实现/证据 | 状态 |
| --- | --- | --- |
| 加权 GPA、0/null、空/全未评分、无提前 round | services/gpa_calculator.dart；test/gpa/gpa_calculator_test.dart | 通过 |
| 有限量表/学分/成绩、重复 ID、乘法和求和溢出、输入不变 | 同上，算法独立复核，ArgumentError | 通过；非法 Course 仅在测试用子类中注入 |
| GpaResult 冻结字段 | 首批 models/gpa_result.dart | 保留且测试通过 |
| 注入正式 EntityRepository<Course>，load/retry/result/isLoading/error | controllers/gpa_controller.dart | 通过；筛选学期、最新请求优先、dispose 后忽略结果 |
| 编辑成绩写回同一仓库，0 有效，空白转 null，错误可见 | presentation/gpa_page.dart；Controller.setGradePoint | Widget 和真实仓库集成测试通过 |
| 学期选择、空数据、loading/error/retry、长文本、小窗口 | test/gpa/gpa_page_test.dart，240×320 | Widget 通过 |
| K 包含/相交/相接/空/单项/重复/排序/不修改输入 | 首批 conflict_detector.dart 与现有10项测试 | 保留，通过 |
| G 正式课次展开 → I 正式 DayScheduleService → K | test/gpa/gpa_conflict_integration_test.dart | 真实类型与服务集成通过；合成日程明确标注 |
| G 正式仓库 → J 编辑 → A/N GPA 回调 | composition/gpa_composition.dart；gpa_controller_test.dart | 真实仓库及回调通过，无生产替身 |
| N 页面/服务消费 GPA | 当前 main 的 Dashboard 仍是占位页；远程 #14 分支只有展示/状态基础 | 未执行，待 N/A 正式服务接入；不能称整项验收完成 |
| Windows 构建、启动、显示 GPA 页面 | flutter run -d windows；同路由快捷入口 example/gpa_demo.dart；evidence/gpa-windows.png | 已执行成功 |
| Windows 人工编辑、学期切换、返回、小窗口、错误恢复 | 桌面自动化取证不稳定，不以 Widget 结果替代 | 尚需组长/本人在原生窗口逐项确认 |
| Android | 无已配置 SDK | 未执行 |

## 检查结果

Flutter 3.44.6 stable / Dart 3.12.2；Windows x64。

- 最新 main 原始基线：flutter test 238/238，通过，退出0。
- flutter pub get：退出0，lock和依赖未变。
- 本人文件 dart format：退出0。
- dart format --output=none --set-exit-if-changed lib test：退出0，79文件0变化。
- flutter analyze：退出0，No issues found。
- flutter test --reporter expanded：退出0，254/254，通过；保留238，新增16。
- flutter run -d windows：实际构建与启动成功；后续同路由快捷入口也构建成功。
- git diff --check：通过。

首次回归发现一次性初始化 Future 跨重复页面测试复用会卡 loading，已修复：初始化成功后清除 Future。全部原导航测试已保留，只将 GPA 主体断言由占位文字改为正式 GpaPage，重新8/8及全量254/254通过。小窗口测试首次未滚动到很长卡片下的按钮，已按实际可点击位置滚动，不关闭命中警告或校验。

## 精确导入、构造、调用

```dart
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/gpa/services/gpa_calculator.dart';
import 'package:student_life_rpg/features/gpa/controllers/gpa_controller.dart';
import 'package:student_life_rpg/features/gpa/composition/gpa_composition.dart';
import 'package:student_life_rpg/features/gpa/presentation/gpa_page.dart';

// courseRepository 为 G 正式仓库；先由 A 完成学期引用装配。
final assembly = GpaComposition(
  courseRepository: courseRepository,
  scoreScaleMax: 4.0, // 明确演示规则，不代表学校官方制度。
);
final controller = await assembly.createController();
await controller.load(semesterId: semesterId);
await controller.setGradePoint(courseId, 0); // 零成绩有效
await controller.setGradePoint(courseId, null); // 清空为未评分
await controller.retry();
final page = GpaPage(composition: assembly);
// A/N：注入此回调，不另算 GPA；与页面读取同一仓库。
final loadGpa = () => assembly.loadGpa(semesterId: semesterId);
// DashboardService(loadGpa: loadGpa, ...) 在 N 正式服务合并后接入。
controller.dispose();
```

Course 正式构造必填 `id/semesterId/name/credits/slots/scoreScaleMax`；可空 `gradePoint`。Controller 更新时完整保留原ID、学期、名称、学分和 slots。

当前应用组合根 `AppRoutes.gpaComposition` 持有同一个正式内存课程仓库，GPA路由传给页面；A可将自己的课程仓库构造成同一 GpaComposition，注入页面及上述回调。默认装配显式 `inMemoryDemo()`，用正式学期/课程仓库互相检查引用，合成课程不冒充用户数据。所有课程均只存内存，重启不保留。评分上限从外部注入，算法不强制4.0。

K示例证据：2026-10-12合成数学课09:00–10:00，由G正式 occurrencesForDate 展开；I汇总09:30–10:30事件；K输出交集09:30–10:00。运行 `flutter test test/gpa/gpa_conflict_integration_test.dart` 可复核。

## 原生复核步骤和限制

`flutter run -d windows`：卧室 → Menu → GPA。或 `flutter run -d windows -t example/gpa_demo.dart` 直接进入同一应用GPA路由。

1. 初始全部学期 GPA 2.64（18.5/7），未评分1门。
2. 英语编辑为0：GPA变1.85（18.5/10），已评分3门。
3. 英语清空：恢复2.64；选择2027春季只见零成绩，GPA为0.00。
4. 选择2026秋季：GPA3.70，未评分1门；检查返回、再进入数据仍在当前进程内。
5. 缩小窗口，滚动并编辑；非有限数/越界表单提示，不写仓库。

loading/read/write/retry故障已用隔离测试注入原始异常验证；生产未添加人为制造故障按钮。Android、N页面联调及上述原生人工交互未执行项不能勾通过。无持久化和自动奖励，不新增趋势或目标规划。PR用Refs #12，由陈思翰审核，Issue保持打开直到剩余验收完成。