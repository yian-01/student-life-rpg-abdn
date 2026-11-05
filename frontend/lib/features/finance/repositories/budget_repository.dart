import '../../../app/data/campus_store.dart';
import '../models/budget.dart';

/// 分类月度预算仓库（持久化契约 v2 的 budgets 表）。
///
/// 引用保护由 CampusStore 全量校验保证：`categoryId` 必须引用已存在的
/// 支出分类；`(categoryId, month)` 组合唯一，重复插入会被拒绝。
class BudgetRepository extends CampusRepository<Budget> {
  BudgetRepository(CampusStore store)
    : super(store, 'budgets', Budget.fromJson, (v) => v.toJson());

  /// 返回指定月份（`YYYY-MM`）的全部预算，按插入顺序。
  Future<List<Budget>> listForMonth(String month) async =>
      List.unmodifiable((await list()).where((b) => b.month == month));

  /// 返回指定分类的全部预算，按插入顺序。
  Future<List<Budget>> listForCategory(String categoryId) async =>
      List.unmodifiable(
        (await list()).where((b) => b.categoryId == categoryId),
      );

  /// 查询指定分类在指定月份的预算，不存在返回 null。
  Future<Budget?> forCategoryMonth(String categoryId, String month) async {
    for (final budget in await list()) {
      if (budget.categoryId == categoryId && budget.month == month) {
        return budget;
      }
    }
    return null;
  }
}
