import '../../../app/data/campus_store.dart';
import '../models/budget.dart';
import 'budget_repository.dart';

/// [BudgetRepository] 的持久化实现：把预算落到 CampusData v2 的 `budgets` 表。
///
/// 行格式沿用 finance 模块的 [Budget] 模型，额外带一个派生 `id`（= [Budget.key]），
/// 供 [CampusStore] 的通用行标识、唯一性与变更检测使用；
/// 解码时先去掉 `id`，其余字段与模型严格对应。
///
/// 引用保护由 [CampusStore] 的全量校验承担：`categoryId` 必须指向支出分类，
/// `(categoryId, month)` 组合唯一，删除被预算引用的分类会被拒绝。
class CampusBudgetRepository implements BudgetRepository {
  CampusBudgetRepository(this._store);

  final CampusStore _store;

  /// [referencedCategoryIds] 是同步接口，因此以最近一次读取/写入的结果作为缓存。
  Set<String> _referenced = const {};

  static Map<String, dynamic> _encode(Budget budget) => {
    ...budget.toJson(),
    'id': budget.key,
  };

  static Budget _decode(Map<String, dynamic> row) {
    final json = Map<String, dynamic>.from(row)..remove('id');
    return Budget.fromJson(json);
  }

  static int _compare(Budget a, Budget b) {
    final byMonth = a.month.compareTo(b.month);
    return byMonth != 0 ? byMonth : a.categoryId.compareTo(b.categoryId);
  }

  @override
  Future<List<Budget>> list() async {
    final budgets = (await _store.rows('budgets')).map(_decode).toList()
      ..sort(_compare);
    _referenced = {for (final budget in budgets) budget.categoryId};
    return List.unmodifiable(budgets);
  }

  @override
  Future<Budget?> getForCategoryMonth(String categoryId, DateTime month) async {
    _requireCategoryId(categoryId);
    final key = budgetKey(categoryId, month);
    for (final row in await _store.rows('budgets')) {
      if (row['id'] == key) return _decode(row);
    }
    return null;
  }

  /// 同一类别+月份的唯一键视为同一行，因此这里是“新增或替换”语义。
  @override
  Future<void> put(Budget budget) async {
    await _store.mutate('budgets', budget.key, _encode(budget), 'put');
    _referenced = {..._referenced, budget.categoryId};
  }

  @override
  Future<bool> removeForCategoryMonth(String categoryId, DateTime month) async {
    _requireCategoryId(categoryId);
    final key = budgetKey(categoryId, month);
    final removed = await _store.mutate('budgets', key, null, 'remove');
    if (removed) {
      _referenced = {..._referenced}..remove(categoryId);
    }
    return removed;
  }

  /// 注意：为同步接口，值来自最近一次 [list] / [put] / [removeForCategoryMonth]。
  /// 分类删除的真正拦截在 [CampusStore] 校验阶段完成。
  @override
  Set<String> referencedCategoryIds() => _referenced;

  static void _requireCategoryId(String categoryId) {
    if (categoryId.trim().isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'Must not be blank.');
    }
  }
}
