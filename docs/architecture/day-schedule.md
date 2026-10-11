# I：单日日程

状态：随 Issue #9 分支 `feat/9-task-day-schedule` 提交。真实课程发生项依赖 #10（G），
持久化依赖 #7（O），当前用注入回调与内存仓库。

## 输入与组合

- 组合：`ScheduleComposition` 把 Task/Event 仓库与课程发生项回调组装为
  `DayScheduleService`，由组合根（A）用真实仓库构造；`inMemoryDemo` 仅供演示。
- 课程接入缝：`CourseOccurrencesForDate = Future<List<ScheduleItem>> Function(DateTime)`，
  由 A/I 组合把 G 的同步单课程算法适配为异步汇总，不建立第二套课程模型。
- 页面：`/schedule` → `SchedulePage`（宿主，持有并释放 Controller）→
  `DaySchedulePage`（纯展示，构造注入 Controller）。

## 日期交集

```text
dayStart = 当地 date 00:00
dayEnd   = 次日本地 00:00
显示条件  = item.start < dayEnd && item.end > dayStart
```

`23:30-次日00:30` 在两天显示并标记跨日；`23:00-次日00:00` 只在首日显示。

## 排序

日程项依次按 `range.start`、`range.end`、sourceType（course、event、task）、`id`。
未安排任务按非空 `dueAt` 升序、空 `dueAt` 最后、再按 `id`。

## 页面状态

- 前一天、后一天；加载时不使用永久 spinner。
- 错误与重试；空日程与空未安排任务。
- 课程、事件、任务标签；已完成标记；跨日提示。
- 新增任务（标题 + 预计分钟，浮层按钮），写入 TaskRepository 后刷新当天。
- 已排程任务与未安排任务可勾选完成/未完成，刷新后由 `completedTaskIds` 反映。
- 未注入 TaskRepository 时不显示编辑入口，页面退化为只读。
- 小窗口与长标题不产生溢出（Widget 测试覆盖 240×320 视口与超长标题）。

Controller 通过 `_requestId` 防止旧请求覆盖新请求，`dispose` 后不再通知监听者。
