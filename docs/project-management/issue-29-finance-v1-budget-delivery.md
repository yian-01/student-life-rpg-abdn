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
| 全套测试 | `flutter test` | 483 项全部通过（含新增 29 项 Budget + 13 项分类管理） |
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
| F-1 | 分类月度预算未接入 `FinancePage` 与根路由 | 中 | 待集成 | 依赖组长接线 |
| F-2 | 预算未接共享持久化，重启不保留 | 中 | 待集成 | 依赖李雨真存储 |
| F-3 | 分类管理入口未闭环 | 中 | 待办 | 独立子任务 |
| F-4 | 新建收支表单缺独立日期字段 | 低 | 既有 | 非本轮范围 |
| F-5 | Android/Windows 原生验收未执行 | 中 | 未测 | 待接入后补 |

### 5.2 结论

- 本轮完成 Budget 领域模型、内存仓库、控制器与表单组件及测试，
  `dart format`/`flutter analyze`/`flutter test` 全部通过。
- 尚未接入正式应用与持久化，不宣称“分类月度预算”功能整体闭环；
  上述缺陷项须由对应负责人集成后再做原生验收。

## 6. 分类管理增量（同分支追加）

- 新增/改名/删除分类：`FinanceController.addCategory/editCategory/deleteCategory`。
- 空白名称：模型抛出 `ArgumentError`，控制器面化为错误。
- 同类型下同名分类（大小写不敏感、trim 后比较）被拒绝。
- 被记录引用时阻止删除与类型修改，并说明原因。
- 被预算引用时阻止删除与类型修改，并说明原因。
- 类型与记录匹配沿用既有 `_assertCategoryMatches`。
- 重命名后刷新可用分类列表与摘要；UI 入口为 `FinancePage` AppBar “分类管理”。
- 测试：`finance_category_management_test.dart` 13 项全部通过。

## 7. V1 收口增量：预算已用/剩余/超支与新增日期联动（2026-11-10）

基线：`e0e38b5`（`fix/v1-review-integration`，Issue #58 临时开发基线）。
分支：`fix/v1-finance-followup`。Flutter 3.44.6 / Dart 3.12.2。

### 7.1 本轮完成

- `FinancePage` 内嵌 `BudgetSection`，逐支出类别显示：
  - 未设置：`未设置预算 · 已用 X 元`，金额位显示 `—`，不虚构额度。
  - 已设置：`已用 X 元 · 剩余 Y 元`；超支显示 `已用 X 元 · 超支 Y 元`
    并使用错误色，剩余保持负数、不截 0。
  - `0` 预算为有效预算，与“未设置”分开显示。
- 已用金额直接取月汇总的 `expenseByCategory`，收入与其他类别不抵减该类别预算；
  页面与总览共用 `FinanceSummaryService`，未复制金额算法。
- 预算保存完成后自动重新读取月汇总，总额剩余与分类状态同步更新。
- 生产 `CampusData.financeService` 的 `loadBudget` 改为汇总当月经
  `CampusBudgetRepository` 持久化的分类预算；无预算仍返回 `null`，不显示 0。
- 新建账目表单新增日期字段，默认注入时钟的“今天”；切换月份时日期跟随到
  目标月份（保留日号，月底自动截断）。
- 保存跨月日期后列表自动切换到该记录所在月份；日期与当前浏览月份不一致时，
  表单提示“保存后将切换到 YYYY-MM”，确保一次录入后能找到记录。
- 金额空/字母/0/负数/小数超精度/上限仍由 `parseAmountMinor` 拒绝；保存期间
  `isSaving` 阻止快速连点重复写入。

### 7.2 执行结果（本机 macOS / Dart 3.12.2）

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 依赖 | `flutter pub get` | 通过 |
| 格式化 | `dart format --output=none --set-exit-if-changed lib test` | 通过（170 文件，0 改动） |
| 静态分析 | `flutter analyze` | `No issues found!` |
| 财务与接线定向测试 | `flutter test test/features/finance test/app/data/v1_repository_wiring_test.dart` | 83 项全部通过 |
| 全套测试 | `flutter test` | 572 项全部通过 |
| Windows 原生运行 | `flutter run -d windows` | 未执行 |
| Android 原生运行 | `flutter run -d android` | 未执行 |

新增/更新的覆盖：
- `budget_widget_test.dart`：已用/剩余（100 预算、35.50 支出 → 64.50）、
  其他类别不抵减、超支负剩余、0 预算超支、未设置不显示虚构额度。
- `finance_page_test.dart`：默认今天、月份切换带动日期、跨月日期保存后切换列表、
  分类预算状态与月总额同步、预算保存后总额刷新。
- `finance_controller_test.dart`：指定日期写入并切换月份；UTC 日期拒绝且不改月份。
- `v1_repository_wiring_test.dart`：生产仓库预算 → 月汇总 `budgetMinor` /
  `remainingBudgetMinor` / `expenseByCategory`。

### 7.3 剩余与阻塞

- Android/Windows 原生运行、真实软键盘与大字体设备复测：未测，需在集成后补。
- #58 尚未合入；后续 PR 仍指向 `feat/app-final-integration`，当前分支不单独合并。
- 独立复核（李雨真保存链路、龙梓瑄月汇总）与组长集成仍待完成。

