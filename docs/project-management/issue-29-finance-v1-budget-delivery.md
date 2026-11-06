# Issue #29（L/M 财务）V1.0 增量交付记录 — 分类月度预算

负责人：吴昕玥。关联总控：#29。时区：北京时间 UTC+8。
基线：`origin/feat/app-final-integration` @ `fcab531`（PR #28）。
分支：`fix/v1-finance`。Flutter 3.44.6 stable / Dart 3.12.2（不升级依赖）。

## 1. 交付范围（本轮）

- 新增 `Budget(categoryId, month, amountMinor)` 领域模型：
  - 唯一性：同一支出类别 + 本地年月仅一项，键为 `budgetKey(categoryId, month)`。
  - 金额以整数“分”表示；`0` 为有效预算，与“未设置”（无预算项）严格区分。
  - 月份归一化为本地月首；拒绝 UTC。
- 新增 `BudgetRepository` 接口与 `InMemoryBudgetRepository`：
  - 以类别+月为键的 upsert，天然保证唯一；引用类别必须存在且为支出类型。
- 新增 `BudgetController`（ChangeNotifier）：加载当月预算、设置/清除、错误面与
  最新请求胜出、dispose 后不再通知。
- 新增预算表单与可嵌入区块 `BudgetSection` / `BudgetEditorDialog`。
- 测试：模型、仓库、控制器、Widget 共 29 项（详见第 4 节）。

D1 契约（已提供）：由 `Budget` 类与 `budgetKey` 表达，见
`frontend/lib/features/finance/models/budget.dart`。

## 2. 明确不在本轮（现状与边界）

- 持久化：由李雨真统一接共享存储；本轮仅内存实现，重启不保留（已在类注释标注）。
- 根路由/主题：由组长接入；本轮未改动 `FinancePage`/`FinanceMemoryScope`。
- 分类管理入口：未闭环，本轮不新建分类 CRUD 页面。
- 分类月度预算接入 `FinancePage`：未闭环，本轮提供可嵌入组件而非页面接线。
- 新建收支表单缺独立日期字段（沿用注入时钟的“现在”）；非本轮范围。
- 现有“收支记录/月汇总/编辑删除和保存”沿用既有实现与测试，未在本轮改动。

## 3. 执行结果（本轮本机，macOS / Dart 3.12.2）

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 依赖 | `flutter pub get` | 通过 |
| 格式化 | `dart format --output=none --set-exit-if-changed lib test` | 通过（151 文件，0 改动） |
| 静态分析 | `flutter analyze` | `No issues found!` |
| 新增测试 | `flutter test .../budget_*` | 29 项全部通过 |
| 全套测试 | `flutter test` | 490 项全部通过（含新增 29 项 Budget + 13 项分类管理 + 7 项文件持久化） |
| Windows 原生运行 | `flutter run -d windows` | 未执行 |
| Android 原生运行 | `flutter run -d android` | 未执行 |

> 说明：本轮为模型/表单/控制逻辑增量，尚未接入正式应用路由与持久化，
> 因此不提供 Android/Windows 正式应用证据；不得以内存/Widget 测试替代原生验收。

## 4. 验收表

| 需求 | 实现 | 测试 | 状态 |
| --- | --- | --- | --- |
| `Budget(categoryId, month, amountMinor)` 契约 | `models/budget.dart` | `budget_model_test.dart` | 通过 |
| 同支出类别+本地年月唯一 | `budgetKey`、`InMemoryBudgetRepository.put` | `budget_model_test.dart`、`budget_repository_test.dart` | 通过 |
| 金额整数分、0 有效、null≠未设置 | `Budget`、`BudgetController.budgetFor` | `budget_model_test.dart`、`budget_controller_test.dart` | 通过 |
| 月份归一化并由 UTC 拒绝 | `_normalizeMonth` | `budget_model_test.dart`、`budget_repository_test.dart` | 通过 |
| 引用校验（存在且为支出类别） | `InMemoryBudgetRepository.put` | `budget_repository_test.dart`、`budget_controller_test.dart` | 通过 |
| 设置/清除/错误面/最新请求胜出 | `BudgetController` | `budget_controller_test.dart` | 通过 |
| 表单保存边界、失败保留输入、0 有效 | `BudgetEditorDialog` | `budget_widget_test.dart` | 通过 |
| JSON 往返与非法输入拒绝 | `Budget.toJson/fromJson` | `budget_model_test.dart` | 通过 |

## 5. 缺陷 / 结论模板（保留）

### 5.1 缺陷清单

| 编号 | 描述 | 严重度 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| F-1 | 分类月度预算接入 `FinancePage` 与根路由 | 中 | 待集成 | 依赖组长接线 |
| F-2 | 文件存储已接通；应用数据目录注入仍待组合根接入 | 中 | 部分完成 | 依赖陈思翰接线 |
| F-3 | 分类管理入口已提供；根路由/主题接线待组长 | 低 | 部分完成 | 独立子任务 |
| F-4 | 新建收支表单缺独立日期字段 | 低 | 既有 | 非本轮范围 |
| F-5 | Android/Windows 原生验收未执行 | 中 | 未测 | 待接入后补 |

### 5.2 结论

- 本轮完成 Budget 领域模型、仓库、控制器、表单，分类管理，以及文件持久化与
  跨月/跨类摘要、提交/刷新分离、金额校验、快速连点去重等测试；
  `dart format`/`flutter analyze`/`flutter test` 全部通过。
- 文件存储（`FinanceFileScope` + `FileJsonDocumentStore`）已可退出重开不丢；
  应用数据目录注入与原生验收由组合根负责人接入后补齐。

## 6. 分类管理增量（同分支追加）

- 新增/改名/删除分类：`FinanceController.addCategory/editCategory/deleteCategory`。
- 空白名称：模型抛出 `ArgumentError`，控制器面化为错误。
- 同类型下同名分类（大小写不敏感、trim 后比较）被拒绝。
- 被记录引用时阻止删除与类型修改，并说明原因。
- 被预算引用时阻止删除与类型修改，并说明原因。
- 类型与记录匹配沿用既有 `_assertCategoryMatches`。
- 重命名后刷新可用分类列表与摘要；UI 入口为 `FinancePage` AppBar “分类管理”。
- 测试：`finance_category_management_test.dart` 13 项全部通过。

## 7. 真实存储与一致性增量（同分支追加）

- `FileFinanceCategoryRepository` / `FileFinanceRecordRepository` /
  `FileFinanceBudgetRepository`：基于共享 `JsonDocumentStore` 的单实体文档
  `{schemaVersion:1, entityType, records}`，写入成功后才提交内存状态。
- `FinanceFileScope.open(directory:)`：装配文件仓库、控制器与汇总服务；
  预算月汇总 = 当月各分类预算之和（无预算返回 null）。
- 保存/刷新分离：一次提交成功后，刷新失败仅展示错误，不重复 insert。
- 跨月份/跨类别编辑记录后，按月摘要与分类聚合随之刷新正确。
- 金额校验沿用 `parseAmountMinor`：空/字母/0/负数/超两位小数/超上限均拒绝。
- 快速连点由 `_isSaving` 与仓库重复 ID 检查共同防止重复/悬空数据。
- 测试：`finance_file_persistence_test.dart` 7 项全部通过。

