// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../../shared/repositories/entity_repository.dart';
import '../models/budget.dart';
import '../models/finance_category.dart';
import '../models/finance_type.dart';
import '../models/local_date_time_json.dart';
import '../models/money.dart';
import '../repositories/budget_repository.dart';

/// 分类月度预算的控制逻辑（V1.0 增量，Issue #29）。
///
/// 只负责读取、设置、清除当前月份的支出类别预算；持久化与根路由由其他
/// 负责人接入。`null` 表示该类别本月未设置预算，`0` 表示设置了 0 元预算。
class BudgetController extends ChangeNotifier {
  BudgetController({
    required BudgetRepository budgets,
    required EntityRepository<FinanceCategory> categories,
    DateTime Function()? clock,
    DateTime? initialMonth,
  }) : _budgets = budgets,
       _categories = categories,
       _clock = clock ?? DateTime.now {
    final now = _clock();
    requireLocalDateTime(now, 'now');
    _month = initialMonth == null
        ? DateTime(now.year, now.month)
        : DateTime(initialMonth.year, initialMonth.month);
  }

  final BudgetRepository _budgets;
  final EntityRepository<FinanceCategory> _categories;
  final DateTime Function() _clock;

  late DateTime _month;
  bool _isLoading = false;
  bool _isSaving = false;
  Object? _error;
  Map<String, Budget> _budgetsByCategory = const {};
  List<FinanceCategory> _expenseCategories = const [];
  int _loadToken = 0;
  bool _disposed = false;

  DateTime get month => _month;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  Object? get error => _error;
  List<FinanceCategory> get expenseCategories => _expenseCategories;

  /// 当月已设置的预算，按类别 ID 升序，返回不可变列表。
  List<Budget> get budgets => List<Budget>.unmodifiable(
    _budgetsByCategory.values.toList()
      ..sort((a, b) => a.categoryId.compareTo(b.categoryId)),
  );

  /// 该类别本月预算金额（分）；未设置返回 null，设置了 0 返回 0。
  int? budgetFor(String categoryId) =>
      _budgetsByCategory[categoryId]?.amountMinor;

  bool isBudgetSet(String categoryId) =>
      _budgetsByCategory.containsKey(categoryId);

  Future<void> load({DateTime? month}) async {
    if (_disposed) return;
    if (month != null) {
      requireLocalDateTime(month, 'month');
      _month = DateTime(month.year, month.month);
    }
    await _loadCurrent();
  }

  Future<void> refresh() => _loadCurrent();

  Future<void> retry() => _loadCurrent();

  /// 设置/更新某支出类别本月预算。金额文本按分解析，允许 0。
  Future<bool> setBudget({
    required String categoryId,
    required String amountText,
  }) => _write(() async {
    final amountMinor = parseAmountMinor(amountText, allowZero: true);
    final category = await _categories.getById(categoryId);
    if (category == null) throw StateError('Unknown finance category');
    if (category.type != FinanceType.expense) {
      throw StateError('Budget requires an expense category');
    }
    await _budgets.put(
      Budget(categoryId: category.id, month: _month, amountMinor: amountMinor),
    );
  });

  /// 清除某类别本月预算。未设置时抛出 StateError。
  Future<bool> removeBudget(String categoryId) => _write(() async {
    if (!await _budgets.removeForCategoryMonth(categoryId, _month)) {
      throw StateError('No budget set for this category/month');
    }
  });

  Future<bool> _write(Future<void> Function() action) async {
    if (_disposed || _isSaving) return false;
    _isSaving = true;
    _error = null;
    notifyListeners();
    var committed = false;
    try {
      await action();
      committed = true;
    } catch (error) {
      _fail(error);
    } finally {
      _isSaving = false;
      if (!_disposed) notifyListeners();
    }

    // 提交已成功；刷新失败只展示错误，不把成功写入伪装成可重试。
    if (committed && !_disposed) {
      await _loadCurrent();
    }
    return committed;
  }

  void _fail(Object error) {
    if (_disposed) return;
    _error = error;
    notifyListeners();
  }

  Future<void> _loadCurrent() async {
    if (_disposed) return;
    final requestedMonth = _month;
    final token = ++_loadToken;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final allBudgets = await _budgets.list();
      final categories = await _categories.list();
      if (_disposed || token != _loadToken) return;

      final forMonth = <String, Budget>{};
      for (final budget in allBudgets) {
        if (budget.month == requestedMonth) {
          forMonth[budget.categoryId] = budget;
        }
      }
      _budgetsByCategory = forMonth;
      _expenseCategories = List<FinanceCategory>.unmodifiable(
        categories.where((category) => category.type == FinanceType.expense),
      );
      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (error) {
      if (_disposed || token != _loadToken) return;
      _isLoading = false;
      _error = error;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadToken++;
    super.dispose();
  }
}
