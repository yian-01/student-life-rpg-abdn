# #32 日程最终整改增量与验收记录

负责人：钟顺成。开工：2026-11-06；本轮检查完成：2026-11-07 00:34（北京时间）。
分支：`fix/v1-schedule-followup`；固定基线：`e0e38b5019d76d1219b3fcd400d742417b937494`（#58）。
旧 `fix/v1-schedule@4d23dbe`／PR #57 保留，原成果及作者历史已在候选中，本轮只认候选后的增量。
环境：Windows，Flutter 3.44.6 stable／Dart 3.12.2；依赖未升级。

状态：代码自验通过，Windows Release 构建通过，原生操作验收未完成。最终 SHA 和该提交的 CI 链接见本 PR；不以 #58 历史561项结果代替本轮检查。

本轮实际执行：`flutter pub get` 成功；`dart format --output=none --set-exit-if-changed lib test` 退出0（174文件、0改动）；`flutter analyze` 退出0（No issues found）；`flutter test` 退出0（581项全部通过，比固定候选增加20项）；`flutter build windows --no-pub` 退出0。完整输出见 [自验记录](evidence/20261106-schedule-followup/checks.md)。正式应用的 `flutter run -d windows` 交互及进程重启验收尚未执行，不能用构建结果替代。

## 实现与接口

| 要求 | 实际文件／符号 | 精确行为、生产消费关系 | 测试 |
|---|---|---|---|
| 真实考试 | `TaskScheduleAdapter.examToScheduleItem`、`DayScheduleService` | `data.exams` → `exam`来源，原ID／完整range；更新删源后刷新不留副本 | `academic_schedule_integration_test.dart`、`academic_schedule_page_test.dart` |
| 独立作业截止 | `DaySchedule.assignmentDeadlines` | `data.assignments` → 当日截止；无伪TimeRange、无Task副本、无时段冲突 | 同上 |
| 稳定排序／跨日／冲突 | 日程服务、既有`findConflicts` | start/end/course/event/task/exam/id；半开区间；完成任务不计冲突，算法未改 | 真实文件混合测试与既有冲突测试 |
| 正确详情／编辑删除 | `ScheduleRecordPage`、`ScheduleRecordController<T>` | 原仓库按sourceId读取，复用学术／事件编辑器；课程只去正式管理 | 页面联动、取消／失败／重复操作测试 |
| 错误隔离／恢复 | `TaskScheduleHost`、`DaySchedule.errors`、Controller | Task与Campus分别提示；健康来源显示；显式恢复复用原接口，保留选中日 | 单坏／双坏真实文件测试、正式路由取消恢复测试 |
| 日期／异步／窄屏 | 日程页面、任务表单 | 日期选择／今天／跨月年；旧请求忽略；320/390/430、大字体、键盘滚动 | 既有体验测试新增320；正式主题完整工具栏测试 |
| 文件重读 | 真实`CampusStore`／`FileTaskRepository` | 五来源CRUD后重建两个仓库，按日结果一致 | SC14文件测试，**不等于进程冷启动** |

必要共享增量是 `ScheduleSourceType.exam`、日程可选仓库参数及结果字段，详见 [接口说明](../architecture/day-schedule.md)。需 #34／共享维护者和组长复核；未复制实体、未改 `conflict_detector.dart`、存储格式或依赖。

```dart
import 'package:student_life_rpg/app/app_data.dart';
import 'package:student_life_rpg/features/schedule/presentation/schedule_page.dart';

final tasks = await AppData.tasks();
final data = await AppData.campus();
final day = await data.schedule(tasks).loadDay(DateTime(2026, 11, 6));
// day.items: 课程／事件／已安排任务／考试。
// day.assignmentDeadlines: 仅当日作业截止；day.errors: 原始读取错误。
// 正式路由使用 TaskScheduleHost，含真实详情、管理与恢复接线。
final page = SchedulePage(loader: data.schedule(tasks), taskRepository: tasks);
```

生产没有新建内存替身：使用 `data.courses`、`data.events`、`data.exams`、`data.assignments` 和同一个 TaskRepository。测试用内存文档／仓库只隔离交互，真实文件测试使用临时目录。默认独立演示构造仍明确显示“演示数据：仅存内存，退出后不保留”，不作为正式入口或持久化证据。

## SC01–SC14 验收矩阵

下列“自动”对应本轮581项全部通过的测试套件；Windows／Android未执行项不勾通过。

| ID | 验证与预期 | 自动证据 | Windows原生 | Android原生 | 生产仍用替身 |
|---|---|---|---|---|---|
| SC01 | 五来源共存，时段与截止分区，分别打开原详情 | 真实文件／正式路由测试 | 待用户录像 | 未执行，无设备 | 否 |
| SC02 | 考试新增、改至闰日、旧日移除、删除，重读无副本 | 文件／正式路由测试 | 未执行 | 未执行 | 否 |
| SC03 | 23:30→次日00:10两天显示；00:00结束不占次日 | 三种时段源真实文件测试 | 未执行 | 未执行 | 否 |
| SC04 | 相接不冲突、09:59重叠提示 | 混合冲突／既有算法测试 | 未执行 | 未执行 | 否 |
| SC05 | 课程／事件／任务／考试／考试两两组合，完成任务退出冲突 | 5项10对→完成后6对 | 未执行 | 未执行 | 否 |
| SC06 | 同起止、连续重读，来源排序和ID稳定 | 真实文件重复打开测试 | 未执行 | 未执行 | 否 |
| SC07 | 作业改日、取消、删除同步，始终不是时段 | 真实文件／页面测试 | 未执行 | 未执行 | 否 |
| SC08 | 跨月／跨年／闰日／今天／返回保留日期 | 原日期测试／本轮闰日往返 | 未执行 | 未执行 | 否 |
| SC09 | 清计划不清截止，非法时间保留草稿 | 既有生命周期／编辑测试 | 未执行 | 未执行 | 否 |
| SC10 | Task/Campus单坏双坏、错误隔离、安全恢复及失败保留 | 文件恢复／正式路由取消测试 | 未执行 | 未执行 | 否 |
| SC11 | 快速切日仅最新结果生效 | 既有Controller与页面测试 | 未执行 | 未执行 | 否 |
| SC12 | 保存失败、连点、取消、后台恢复无假成功／副本 | 真实编辑器／Controller测试 | 未执行 | 未执行 | 否 |
| SC13 | 320/390/430，长标题、大字体、键盘，字段错误保存可达 | 真实编辑器＋完整正式主题测试 | 未执行 | 未执行 | 否 |
| SC14 | 五来源CRUD→完全退出进程→重开结果一致 | 文件重建已覆盖，进程测试未执行 | 未执行 | 未执行 | 否 |

## 原S01–S14原生复验

2026-11-02隔离Web记录保持历史，不延续为本轮原生通过。

| ID | 本轮原生复验步骤 | Windows实际 | Android实际 |
|---|---|---|---|
| S01 | 新建无计划无截止任务，45分钟，未安排区唯一出现 | 未执行 | 未执行 |
| S02 | 新建09:00–10:00任务，对应日显示 | 未执行 | 未执行 |
| S03 | 仅截止18:00，不生成计划；重开编辑可读回 | 未执行 | 未执行 |
| S04 | 任务23:30→次日00:30，两天各显示且完整日期 | 未执行 | 未执行 |
| S05 | 改标题／估时／结束，原ID不变无副本 | 未执行 | 未执行 |
| S06 | 清计划保留独立截止 | 未执行 | 未执行 |
| S07 | 完成→取消完成，其他字段保留 | 未执行 | 未执行 |
| S08 | 非今天进入事件管理新增，返回保留选中日并刷新 | 未执行 | 未执行 |
| S09 | 跨日事件两天显示、第三天不显示 | 未执行 | 未执行 |
| S10 | 事件改备注时间／删除，日程同步 | 未执行 | 未执行 |
| S11 | 相等／倒置起止拒绝保存，草稿保留 | 未执行 | 未执行 |
| S12 | 任务／事件修改取消，原数据不变 | 未执行 | 未执行 |
| S13 | 任务／事件删除取消不变，确认删除 | 未执行 | 未执行 |
| S14 | 混合来源按时间排序，切日返回无漏项／重复 | 未执行 | 未执行 |

## 未完成、依赖与贡献边界

- #58固定候选尚待独立复核／合并；本分支可Draft留痕，不提前独立合入。PR基线外共享历史不计本人贡献。
- #31已在候选提供真实作业考试仓库，本轮消费；不再把它们记作“接口不存在”。`fix/v1-academic-import@b6d18a5`批量导入及其后续未在本候选，不重复合入整支，也不声明真实网址导入完成。需统一后按真实源页面验收。
- #34负责混合冲突／边界独立复核，#30负责文件仓库及存储边界。已缓存Task/Campus后外部改坏／丢失文件的读取策略属于存储层，日程不绕过缓存另读文件；当前原仓库可能返回已缓存快照，需#30复核。冷启动坏文件和显式恢复已有自动覆盖。
- #35总览考试／作业接入未包含在本PR，不声称AC11“总览”已通过；日程侧链路可独立联调。
- Windows完整录像／关闭进程重启由用户提供；Android暂无设备，未执行。原生验收、安装升级和真实导入仍未完成，Issue保持未完成。
- 贡献仅本轮日程代码、测试、必要接线和文档；不改学术字段／作业提交状态#42、不升级依赖、不重写他人冲突算法或存储实现。

Windows操作与证据位置见 [人工验收步骤](evidence/20261106-schedule-followup/README.md)。
