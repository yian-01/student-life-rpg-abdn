// ignore_for_file: prefer_initializing_formals

import '../../../shared/repositories/entity_repository.dart';
import '../models/budget.dart';
import '../models/finance_category.dart';
import '../models/finance_type.dart';

/// Repository keyed by [Budget.key]. Implementations must reject duplicate
/// category/month keys as well as duplicate entity IDs.
abstract interface class BudgetRepository {
  Future<List<Budget>> list();

  Future<Budget?> getForCategoryMonth(String categoryId, DateTime month);

  Future<void> put(Budget budget);

  Future<bool> removeForCategoryMonth(String categoryId, DateTime month);

  /// Category IDs that currently have at least one budget (any month).
  /// Used by category management to block deletion/type changes.
  Set<String> referencedCategoryIds();
}

/// Memory implementation for isolated UI/tests; not a persistence substitute.
class InMemoryBudgetRepository implements BudgetRepository {
  InMemoryBudgetRepository({
    required EntityRepository<FinanceCategory> categories,
  }) : _categories = categories;

  final EntityRepository<FinanceCategory> _categories;
  final Map<String, Budget> _budgets = {};

  @override
  Future<List<Budget>> list() async => List<Budget>.unmodifiable(
    _budgets.values.toList()..sort((a, b) {
      final byMonth = a.month.compareTo(b.month);
      return byMonth != 0 ? byMonth : a.categoryId.compareTo(b.categoryId);
    }),
  );

  @override
  Future<Budget?> getForCategoryMonth(String categoryId, DateTime month) async {
    _requireCategoryId(categoryId);
    return _budgets[budgetKey(categoryId, month)];
  }

  @override
  Future<void> put(Budget budget) async {
    final category = await _categories.getById(budget.categoryId);
    if (category == null) {
      throw StateError('Unknown finance category: ${budget.categoryId}');
    }
    if (category.type != FinanceType.expense) {
      throw StateError('Budgets require an expense category.');
    }
    _budgets[budget.key] = budget;
  }

  @override
  Future<bool> removeForCategoryMonth(String categoryId, DateTime month) async {
    _requireCategoryId(categoryId);
    return _budgets.remove(budgetKey(categoryId, month)) != null;
  }

  @override
  Set<String> referencedCategoryIds() =>
      _budgets.keys.map((key) => key.split('@').first).toSet();

  static void _requireCategoryId(String categoryId) {
    if (categoryId.trim().isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'Must not be blank.');
    }
  }
}
