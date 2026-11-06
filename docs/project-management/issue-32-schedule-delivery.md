# Issue #32 日程增量交付记录

负责人：钟顺成  
分支：`fix/v1-schedule`  
基线：`origin/feat/app-final-integration` @ `fcab53102a3f69b08d73a590c0d005daf6aeaca0`  
关联：[#32](https://github.com/yian-01/student-life-rpg-abdn/issues/32)、[#29](https://github.com/yian-01/student-life-rpg-abdn/issues/29)  
环境：Flutter 3.44.6 stable、Dart 3.12.2、Windows 11

## 本轮实现

| 需求 | 实际实现 | 生产方 → 消费方 | 证据 |
| --- | --- | --- | --- |
| 日期标题可选日期并回到今天 | `features/schedule/presentation/day_schedule_page.dart` 的 `_DateNavigator` | `DayScheduleController.loadDay` → 日程页 | `v1_schedule_experience_test.dart` |
| 快速切日只接受最新请求 | 沿用 `DayScheduleController` 请求编号保护，补页面回归 | `DayScheduleLoader` → Controller → 页面 | `v1_schedule_experience_test.dart` |
| 跨日显示完整端点，午夜结束不泄漏 | `_formatRange` 使用本地日期时间；服务继续按 `[dayStart, dayEnd)` 过滤 | `TimeRange` → `DayScheduleService` → 页面 | 日程服务既有测试 + 本轮跨日/跨年测试 |
| 已安排任务显示计划、估时、独立截止 | `_ScheduledTaskDetails` 展开时通过注入的 `TaskRepository` 读取 | `TaskRepository` → Controller → 页面 | 本轮任务详情测试 |
| 未安排任务范围明确 | 页面显示“未安排任务（全部日期）” | `DaySchedule.unscheduledTasks` → 页面 | 本轮空态和跨日期测试 |
| 混合冲突可读且计数一致 | 冲突行显示完整来源类型，标题使用“几对冲突”；完成任务仍显示但从冲突计算排除 | `findConflicts` → Controller → 页面 | 本轮三来源冲突测试、既有冲突测试 |
| 连点保存／事件管理／删除保护 | 事件编辑、删除确认、恢复和日程跳转增加忙状态保护 | 页面回调 → 真实注入 Controller/Repository | 本轮事件重复操作测试、既有任务生命周期测试 |
| 小窗口、键盘和校验错误 | 任务弹窗继续使用 `AlertDialog(scrollable: true)`；本轮覆盖 360/390/430、放大文字、软键盘 inset、错误和提交 | 页面 → TaskEditorDialog | 本轮 3 个窄屏测试 |

页面没有创建仓库。正式宿主继续通过构造注入 `TaskRepository`；未注入仓库的演示装配仍显示“演示数据：仅存内存，退出后不保留”。任务详情也从同一注入仓库读取，未增加第二份日程主数据。

## 验收结果

| 项目 | 实际结果 | 状态 |
| --- | --- | --- |
| `flutter pub get` | 通过；锁定依赖未升级 | 通过 |
| `dart format --output=none --set-exit-if-changed lib test` | 通过；`Formatted 144 files (0 changed)` | 通过 |
| `flutter analyze` | 通过；`No issues found!` | 通过 |
| `flutter test` | 通过；452 项全部通过 | 通过 |
| Windows 编译和启动 | `flutter run -d windows` 成功构建并启动 `student_life_rpg`；最终源码版本已重新编译，窗口可显示卧室入口 | 通过，正式日程逐项手测未完成 |
| Android 原生运行 | 当前 `flutter devices` 未发现 Android 设备或模拟器 | 未执行 |

本轮没有把隔离 Web、Widget 测试或内存替身写成 Windows/Android 原生通过证据。Windows 新增／完成流程截图未作为本 PR 必需文件保存；如组长需要截图，可在合入候选包后由验收人员从正式 Windows 应用重新截取并归档。

## 未完成和依赖

- 作业／考试的真实管理、持久化和日程消费依赖 [#31](https://github.com/yian-01/student-life-rpg-abdn/issues/31) 的实际接口；本 PR 没有复制 `Assignment`、`Exam` 或新增错误来源字符串。
- 冲突展示的共享类型和独立复核依赖 [#34](https://github.com/yian-01/student-life-rpg-abdn/issues/34)；本 PR 只消费当前 `ScheduleItem` 与 `findConflicts`。
- Task 坏文件的显式恢复、迁移和跨进程重启证据依赖 [#30](https://github.com/yian-01/student-life-rpg-abdn/issues/30)；本 PR 没有声称内存仓库具备重启恢复，也没有修改 `FileTaskRepository`。
- 历史 #10／#7 已不作为本分支新增接口来源；若集成分支尚未合入对应真实课程／Task 存储改动，组长必须先合入实际提供方，再由消费方按最新集成分支联调。
- 本 PR 未完成 Android 真机验收、正式 Windows S01–S14 全项人工验收、完全退出重开、坏文件恢复、真实课表网址导入和作业截止联动；这些项目保持未通过或未执行状态。

## 消费方构造与调用示例

```dart
final repository = await AppData.tasks();
final campus = await AppData.campus();
final loader = campus.schedule(repository);

SchedulePage(
  loader: loader,
  taskRepository: repository,
  onManageEvents: (date) => Navigator.of(context).pushNamed<void>(
    '/events',
    arguments: date,
  ),
);
```

日程页保持 `Presentation → Controller → Repository → Storage` 方向。消费方必须传入同一 `TaskRepository` 给 `loader` 所在组合和 `taskRepository` 写入口；不要从 `SchedulePage` 外再创建演示仓库。

