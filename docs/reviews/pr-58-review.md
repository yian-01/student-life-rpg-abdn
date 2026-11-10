# PR #58 独立复核意见

复核人：李雨真
复核日期：2026-11-10
被复核 PR：[#58 fix(integration): restore CI coverage and reconcile V1 module contracts](https://github.com/yian-01/student-life-rpg-abdn/pull/58)

## 1. 复核 SHA

`e0e38b5019d76d1219b3fcd400d742417b937494`

以 detached worktree 独立检出该提交后执行验证，不在本人工作分支上进行，避免把自身增量混入复核对象。

## 2. 代码与测试复查范围

- `frontend/lib/app/data/campus_store.dart`：持久化接线、v1→v2 迁移、引用保护、错误类型
- `frontend/lib/app/data/campus_data.dart`：生产仓库注入与控制器组装
- `frontend/lib/features/schedule/repositories/file_task_repository.dart`：D13 恢复契约
- `frontend/lib/features/finance/`：预算仓库、预算与财务汇总接线
- `frontend/lib/features/academic/repositories/`：作业与考试持久化仓库
- 对应测试：`campus_migration_test.dart`、`campus_persistence_test.dart`、`file_task_repository_test.dart`、`task_recovery_widget_test.dart`

## 3. 实际执行的命令、平台与证据

平台：Windows 11，Flutter 3.44.6 stable（framework revision `ee80f08bbf`）

| 命令 | 结果 |
| --- | --- |
| `dart format --set-exit-if-changed lib test` | 170 files (0 changed)，退出码 0 |
| `dart analyze lib test` | No issues found，退出码 0 |
| `flutter test --no-pub` | 561 项全部通过 |

与 GitHub Actions `build-and-test` success（2026-11-05，4m26s）结论一致，本地独立执行复现了同一结果。

### Windows 原生运行

**构建 A：`followup/storage-txn`（#58 基线 + 存储增量）**
产物 `student_life_rpg.exe`，构建于 2026-11-06 13:22。

| 检查项 | 结果 |
| --- | --- |
| 首屏启动 | 正常，无白屏或报错 |
| 四个入口（日程手账 / 学业档案 / 生活账本 / 仪表盘）进入并返回 | 正常，均能返回大厅 |
| 房间进入后返回，连续 5 次 | 无重复提示、无页面叠加、无崩溃 |
| 新增任务「测试4」（30 分钟） | `tasks.json` 6 → 7 条，写入时间 09:19:38 |
| 彻底关闭后重新打开 | 新进程 PID 7780（首次为 2012），任务保留；二次启动未改写 `tasks.json`（mtime 仍 09:19:38） |
| `.bak` 轮转 | `tasks.json.bak` 为写入前的 6 条版本（1003 字节） |
| 已有 v1 数据自动升级 | 首次启动 `campus.json` 写回 v2（09:16:05），原记录保留 |

**构建 B：纯 `e0e38b5`（本次复核自行构建）**
`flutter build windows --release` 成功（75.7s），产物位于 `%TEMP%\review58\frontend\build\windows\x64\runner\Release\`。

| 检查项 | 结果 |
| --- | --- |
| 启动 | 正常，进程 PID 11528，无崩溃 |
| 读取已有数据 | 能读到「测试4」等 7 条任务，未丢失 |
| 启动时是否改写主文件 | 否，`tasks.json` mtime 仍 09:19:38、`campus.json` 仍 09:16:05，v2 迁移未重复触发 |
| 四入口进出 / 房间连续进出 5 次 | 正常，无重复提示与页面叠加 |

## 4. 已验证通过

- 持久化为真实接线，不是内存桩：`assignments → StoredAssignmentRepository`、`exams → StoredExamRepository`、`budgets → CampusBudgetRepository`；生产路由为 `FinancePage(controller: data.finance, budgetController: data.budgetController, isPersistent: true)`。
- v1→v2 迁移逐表保留原记录，未知 schema 与未知顶层键拒绝；键数按 `tables.length + _baseKeys.length` 动态校验，不依赖硬编码 8。
- 引用保护完整：学期→课程、课程→作业/考试、分类→记录/预算、`(categoryId, month)` 唯一。
- 恢复契约覆盖：单环、双环、缺主有备份、无备份、坏备份、恢复取消、恢复中写失败、归档重名递增，均有用例。
- 普通读取严格只读，不静默恢复；`recoverFromBackup` 先校验备份，再归档损坏原件，最后提交内存。

## 5. 发现的问题

| 级别 | 问题 | 位置 | 建议 |
| --- | --- | --- | --- |
| P1 | 生产接线 `loadBudget: (_) async => null`，用户设置的月预算不会进入 `MonthlyFinanceSummary`，汇总与仪表盘恒无预算 | `campus_data.dart:71` | 改为从 `budgets` 按 month 读取；或明确「预算仅页面级生效」并写入文档 |
| P2 | Task 侧无外部变更检测，外部改写或删除 `tasks.json` 后应用仍会覆盖 | `file_task_repository.dart` | 由 PR #61 的 `_lastDiskRaw` / `_lastWriteFailed` 状态机补齐 |
| P2 | 预算行解码 `row as Map<String, dynamic>`，非对象行抛 `TypeError` 而非契约要求的 `FormatException` | `campus_store.dart` 预算解码段 | 统一收敛为 FormatException |
| P2 | mutate 路径把实体校验的 FormatException 包装成 `StateError('Invalid reference or entity')`，与契约「实体非法 → FormatException」有出入 | `campus_store.dart` | 确认是否有意，否则回退为 FormatException |
| P3 | `FinancePage` 未注入 controller 时静默降级到内存演示数据，不报错 | `finance_page.dart:50-52` | 生产路径已注入不受影响，建议加断言防回归 |

## 6. 未测项与限制说明

- **Android**：由项目成员在真机上执行（安装 `build-artifacts/student-life-android-release.apk`，即 `followup/storage-txn` 构建），前台/后台/重开均正常。该 APK 含存储增量，**非纯 `e0e38b5` 产物**；设备型号与系统版本未记录，未保留 logcat
- **纯 `e0e38b5` 的 Android 产物**：本机无 Android SDK，未构建、未实机验证，本条为客观能力限制
- 上述 Windows 两项构建均由复核人本机独立构建/运行，构建 B 的环境与本机 `flutter test` 一致（Flutter 3.44.6 stable）

## 7. 结论

**可作为整改基线，建议合入。**

- P1 建议就地修复或单独开 issue 挂账，不阻塞合入
- P2 由 PR #61 的存储增量补齐
- 合入前需重新比对 head/base 是否仍为本次复核的 SHA

复核人：李雨真（独立复核，非作者自签）
