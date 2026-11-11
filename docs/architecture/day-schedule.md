# I：单日日程

当前增量：#32，基于 #58 候选 `e0e38b5`，分支 `fix/v1-schedule-followup`。
生产宿主使用同一 `CampusData` 的课程／事件／考试／作业仓库及独立的文件 TaskRepository。
本次共享模型增量须由组长和 #34／共享维护者复核，尚未表示候选已合入集成分支。

## 2026-11-06 日程接口增量

冻结契约中的本地时间、半开区间、JSON、错误及 ID 规则继续适用。本轮按 #29/#32 的11月整改要求新增：

- `ScheduleSourceType.exam` 追加在 `task` 后；未改变既有枚举顺序。
- `DayScheduleService`／`ScheduleComposition` 可选注入 `EntityRepository<Exam>? examRepository`、`EntityRepository<Assignment>? assignmentRepository`，正式 `CampusData.schedule(tasks)` 注入 `data.exams`／`data.assignments`。
- `DaySchedule.assignmentDeadlines`：不可变 `List<Assignment>`，按 `[dayStart, dayEnd)` 筛选 `dueAt`，按截止时间／ID排序。不构造时间范围，不复制 Task，不参与冲突，不假设尚未接入的作业提交状态。
- `DaySchedule.errors`：不可变 `Map<ScheduleDataSource, Object>`，来源为 courses/events/tasks/exams/assignments，保存原始异常；错误来源不能作为成功空列表解读。健康来源正常显示，界面分别提示任务与校园数据失败。
- `TaskScheduleAdapter.examToScheduleItem(Exam)` 保留原始 `sourceId=exam.id` 与完整 `range`，派生 ID 为 `exam:<Uri.encodeComponent(exam.id)>:YYYYMMDD:HHmmssffffff`；小数部分沿用毫秒乘1000加微秒。跨日查询不改变该ID，源时间修改后重新生成。
- 同日起读取错误时保留该来源上次成功数据并显示错误；切日期不携带旧日期数据。恢复成功后从真实仓库重新加载，不复用失败来源的旧快照。
- 日程中的课程／事件／考试分别打开原实体详情；作业截止打开原作业；任务使用任务编辑器。课程修改经 `/academic` 正式管理和引用校验，不直接写课程。
- `ScheduleRecordController<T>` 通过 `EntityRepository<T>` 读取／删除原实体，错误可重试、删除防重。复用既有考试／作业／事件编辑器保留失败草稿。

根装配的必要增量位于 `app/data/campus_data.dart` 与 `app/task_schedule_host.dart`，没有修改存储格式、文件仓库或冲突算法。Dashboard 接入仍由 #35 负责。

## 输入与组合

- 组合：`ScheduleComposition` 把 Task/Event 仓库与课程发生项回调组装为
  `DayScheduleService`，由组合根（A）用真实仓库构造；`inMemoryDemo` 仅供演示。
- 课程接入缝：`CourseOccurrencesForDate = Future<List<ScheduleItem>> Function(DateTime)`，
  由 A/I 组合把 G 的同步单课程算法适配为异步汇总，不建立第二套课程模型。
- 页面：`/schedule` → `SchedulePage`（宿主，持有并释放 Controller）→
  `DaySchedulePage`（纯展示，构造注入 Controller）。
- 装配规则（读取与写入必须落在同一个 `TaskRepository` 上）：

| `loader` | `taskRepository` | 行为 |
| --- | --- | --- |
| 已注入 | 已注入 | 读取用 loader，写入用同一仓库 |
| 已注入 | 未注入 | 只读：隐藏新增/勾选入口 |
| 未注入 | 已注入 | `ScheduleComposition.forTaskRepository` 读取与写入共用该仓库，不注入演示数据 |
| 未注入 | 未注入 | 内存演示装配：显示“演示数据：仅存内存，退出后不保留”，并注入演示数据 |

未注入 `loader` 时不再新建“演示仓库”，因此不会出现读取与写入分离。

## 日期交集

```text
dayStart = 当地 date 00:00
dayEnd   = 次日本地 00:00
显示条件  = item.start < dayEnd && item.end > dayStart
```

`23:30-次日00:30` 在两天显示并标记跨日；`23:00-次日00:00` 只在首日显示。

## 排序

日程项依次按 `range.start`、`range.end`、sourceType（course、event、task、exam）、`id`。
未安排任务按非空 `dueAt` 升序、空 `dueAt` 最后、再按 `id`。

## 页面状态

- 前一天、后一天；加载时不使用永久 spinner。
- 错误与重试；空日程与空未安排任务。
- 课程、事件、任务标签；已完成标记；跨日提示。
- 新增任务（标题 + 预计分钟，浮层按钮），写入 TaskRepository 后刷新当天。
- 已排程任务与未安排任务可勾选完成/未完成，刷新后由 `completedTaskIds` 反映。
- 未注入 TaskRepository 时不显示编辑入口，页面退化为只读。
- 演示装配在页面顶部显示“演示数据：仅存内存，退出后不保留”；真实注入模式不显示且不注入演示数据。
- 新增任务弹窗使用可滚动内容（`AlertDialog(scrollable: true)`），小视口与软键盘弹出时
  输入框、错误提示与提交按钮仍可滚动到并点击。
- 小窗口与长标题不产生溢出（Widget 测试覆盖 240×320 视口与超长标题）。

Controller 通过 `_requestId` 防止旧请求覆盖新请求，`dispose` 后不再通知监听者。
