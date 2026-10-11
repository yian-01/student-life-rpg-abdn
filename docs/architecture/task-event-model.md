# H/I：Task、Event 与单日日程

状态：随 Issue #9 分支 `feat/9-task-day-schedule` 提交。共享类型以
`frontend/lib/shared/` 的实际文件为准，本模块只 import，不另建平行定义。

## 1. H 领域模型

### Task

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| `id` | `String` | 非空，由调用方提供；`copyWith` 不可修改 |
| `title` | `String` | 非空 |
| `estimatedMinutes` | `int` | > 0，仅表示预计分钟 |
| `isCompleted` | `bool` | 构造默认 `false`；持久化 JSON 必填 |
| `dueAt` | `DateTime?` | 本地民用时间，不是排程结束时间 |
| `scheduledRange` | `TimeRange?` | 为空表示未安排 |

`dueAt` 与 `scheduledRange` 独立保存，任何转换都不得由 `dueAt` 反推排程，也不得把
排程结束当作截止时间。

### Event

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| `id` | `String` | 非空，不可修改 |
| `title` | `String` | 非空 |
| `range` | `TimeRange` | 必填，遵守共享半开区间与本地时间校验 |
| `description` | `String?` | 可空 |

Event 不包含任务完成状态。

## 2. Repository 语义

`TaskRepository implements EntityRepository<Task>`，新增
`Future<void> setCompleted(String id, bool isCompleted)`，供 #7 持久化、#12 冲突检测、
#14 下游模块消费。`InMemoryTaskRepository` / `InMemoryEventRepository` 实现该契约：

- `list()` 返回不可变副本。
- `getById` 不存在返回 `null`；`remove` 不存在返回 `false`。
- `insert` 重复 ID 抛 `StateError`；`update` 不存在抛 `StateError`。
- ID 为空白时抛 `ArgumentError`。
- `setCompleted` 幂等，重复设置相同值不产生额外副作用。

## 3. JSON

模型负责单条记录的 `toJson` / `fromJson`；顶层文档（`schemaVersion` /
`entityType` / `records`）由 O 负责。规则：

- 非空字段必须存在；可空字段缺失按 `null` 处理，写出时显式为 `null`。
- `isCompleted` 必须存在且为 `bool`。
- 模型与嵌套对象拒绝未知字段。
- 时间使用无 `Z`、无偏移的本地 ISO 字符串；`Z`、偏移和归一化后的非法日历值
  （如 `2026-02-29`、`24:00:00`）一律抛 `FormatException`。
- JSON 层错误统一为 `FormatException`；构造校验错误在解码层转换。

## 4. 统一日程项与排序

`TaskScheduleAdapter` 只生成共享 `ScheduleItem`：

| 来源 | 是否产生日程项 | `sourceType` |
| --- | --- | --- |
| Event | 总是 | `event` |
| 已排程 Task（含已完成） | 是 | `task` |
| 未安排 Task | 否 | 不适用 |

派生 ID 形如 `<sourceType>:<Uri.encodeComponent(sourceId)>:<YYYYMMDD>:<HHmmssffffff>`，
小数部分为 `millisecond * 1000 + microsecond` 补齐 6 位，避免同秒不同起点碰撞；
`sourceId` 属性保留原值。排序键依次为 `range.start`、`range.end`、sourceType
（course < event < task）、`id`。

## 5. 单日过滤

```text
dayStart = 目标日期当地 00:00
dayEnd   = 次日的当地 00:00
显示条件  = item.start < dayEnd && item.end > dayStart
```

- `23:30-次日00:30` 两天都出现，`isCrossDay` 为真，保留原始完整 range。
- `23:00-次日00:00` 只在首日出现。
- 已完成且已安排 Task 仍显示，由 `completedTaskIds` 标记。
- `unscheduledTasks` 只含未完成且 `scheduledRange == null` 的任务，按非空 `dueAt`
  升序、空 `dueAt` 最后、再按 `id`。

## 6. 页面状态

页面构造注入 `DayScheduleController`，控制器构造注入 `DayScheduleLoader`
（`ScheduleComposition` 或测试替身）；Widget 不创建 Repository。页面覆盖日期切换、
加载、错误重试、空日程、空未安排任务、来源标签、已完成标记与跨日提示。

## 7. 重复任务（未实现）

运行模型不包含 recurrence。`frequency` / `interval` / `until` / `count` / `byWeekday`
以及时区、完成粒度、修改范围、月底日期等边界未获批准，不得先实现。
