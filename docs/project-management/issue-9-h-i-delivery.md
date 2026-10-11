# Issue #9（H/I）交付与验收记录

分支：`feat/9-task-day-schedule`。基线：`main` @ `aa64f1f`。Flutter 3.44.6 stable /
Dart 3.12.2。测试在 `frontend/` 运行。

## 交付范围

- H：`Task`、`Event`、`TaskRepository` 契约、内存 Task/Event 仓库、
  `TaskScheduleAdapter`、模型 JSON 与校验。
- I：`DayScheduleService`（`DaySchedule` 结果）、`DayScheduleController`、
  `DaySchedulePage`、`ScheduleComposition`，并把 `/schedule` 接入真实页面。

## 验收表

| 需求 | 实现 | 测试 | 状态 |
| --- | --- | --- | --- |
| Task/Event 字段与不可变更新 | `models/task.dart`、`models/event.dart` | `task_test.dart`、`event_test.dart` | 通过 |
| `estimatedMinutes > 0`、UTC 拒绝 | `models/task.dart`、`models/local_datetime_json.dart` | `task_test.dart` | 通过 |
| JSON 必填/可空/未知字段/非法值 | `task.dart`、`event.dart` | `task_test.dart`、`event_test.dart` | 通过 |
| CRUD、重复 ID、更新/删除不存在 | `in_memory_*_repository.dart` | `in_memory_repository_test.dart` | 通过 |
| 空白 ID → `ArgumentError` | 两个内存仓库 | `in_memory_repository_test.dart` | 通过 |
| `setCompleted` 幂等 | `in_memory_task_repository.dart`、`task_repository.dart` | `in_memory_repository_test.dart` | 通过 |
| Event / 已排程 / 未排程 Task 适配 | `task_schedule_adapter.dart` | `task_schedule_adapter_test.dart` | 通过 |
| 派生 ID 含编码 sourceId 与 6 位小数秒 | `task_schedule_adapter.dart` | `task_schedule_adapter_test.dart` | 通过 |
| 单日半开区间过滤与排序 | `day_schedule_service.dart` | `day_schedule_service_test.dart` | 通过 |
| 跨日 / 恰好午夜结束 | `day_schedule_service.dart` | `day_schedule_service_test.dart` | 通过 |
| 已完成未安排任务不入未安排区 | `day_schedule_service.dart` | `day_schedule_service_test.dart` | 通过 |
| 加载、导航、错误重试、请求防串扰、dispose | `day_schedule_controller.dart` | `day_schedule_controller_test.dart` | 通过 |
| 空状态、错误重试、长文本、小窗口 | `presentation/day_schedule_page.dart` | `day_schedule_page_test.dart` | 通过 |
| 组合注入真实仓库，不写死内存实现 | `composition/schedule_composition.dart`、`presentation/schedule_page.dart` | `schedule_composition_test.dart` | 通过 |
| 重复任务不进入运行模型 | `docs/architecture/task-event-model.md` | 文档审核 | 通过 |

## 执行结果（2026-10-11，本机 Windows 11）

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 依赖 | `flutter pub get` | 通过 |
| 格式化 | `dart format --output=none --set-exit-if-changed lib test` | 通过（35 文件，0 改动） |
| 静态分析 | `flutter analyze` | `No issues found!` |
| 单元/Widget 测试 | `flutter test` | 64 项全部通过（基线 15 + 新增 49） |
| Windows 原生运行 | `flutter run -d windows --route=/schedule` | 通过，窗口标题 `student_life_rpg`；截图见 `docs/project-management/evidence/` |
| Android 原生运行 | — | 未执行（未安装 Android SDK） |

## 依赖与限制

- 课程发生项：`CourseOccurrencesForDate` 注入，#10 合并后替换为真实结果。
- 持久化：本轮只有 Task 参与 JSON 设计，#7/O 合并后接入存储；内存仓库重启不保留。
- 组合根：`SchedulePage` 已支持注入真实 loader；当前未注入时使用明确标注的内存演示数据。
- 基线 Widget 测试中 `/schedule` 的占位断言按新行为更新，需 A 复核。
