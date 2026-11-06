// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import '../../../shared/repositories/entity_repository.dart';
import '../../../shared/storage/json_document_store.dart';
import 'controllers/budget_controller.dart';
import 'controllers/finance_controller.dart';
import 'models/finance_category.dart';
import 'models/money.dart';
import 'repositories/file_finance_repositories.dart';
import 'services/finance_summary_service.dart';

/// 真实文件存储下的财务关系图：记录 / 分类 / 预算退出重开不丢。
///
/// 组合根（陈思翰）负责注入应用数据目录与平台适配；本类只负责把文件仓库、
/// 控制器和汇总服务装配起来。测试使用临时目录，不触碰用户真实数据。
class FinanceFileScope {
  FinanceFileScope._({
    required this.categories,
    required this.records,
    required this.budgets,
    required this.service,
    required this.controller,
    required this.budgetController,
  });

  static const String categoriesFileName = 'finance_categories.json';
  static const String recordsFileName = 'finance_records.json';
  static const String budgetsFileName = 'finance_budgets.json';

  final FileFinanceCategoryRepository categories;
  final FileFinanceRecordRepository records;
  final FileFinanceBudgetRepository budgets;
  final FinanceSummaryService service;
  final FinanceController controller;
  final BudgetController budgetController;

  EntityRepository<FinanceCategory> get categoryRepository => categories;

  /// 打开（或创建）目录下的财务数据并加载到内存。
  static Future<FinanceFileScope> open({
    required String directory,
    JsonDocumentStore? store,
    DateTime Function()? clock,
    DateTime? initialMonth,
  }) async {
    final documentStore = store ?? const FileJsonDocumentStore();
    final sep = Platform.pathSeparator;

    late final FileFinanceRecordRepository records;
    late final FileFinanceBudgetRepository budgets;

    final categories = FileFinanceCategoryRepository(
      store: documentStore,
      path: '$directory$sep$categoriesFileName',
      recordCategoryIds: () => records.referencedCategoryIds(),
      budgetCategoryIds: () => budgets.referencedCategoryIdsAsync(),
    );
    records = FileFinanceRecordRepository(
      store: documentStore,
      path: '$directory$sep$recordsFileName',
      categories: categories,
    );
    budgets = FileFinanceBudgetRepository(
      store: documentStore,
      path: '$directory$sep$budgetsFileName',
      categories: categories,
    );

    Future<int?> loadBudget(DateTime month) async {
      final all = await budgets.list();
      final start = DateTime(month.year, month.month);
      final forMonth = all.where((budget) => budget.month == start).toList();
      if (forMonth.isEmpty) return null;
      var total = 0;
      for (final budget in forMonth) {
        total = addAmountMinor(total, budget.amountMinor);
      }
      return total;
    }

    final service = FinanceSummaryService(
      records: records,
      categories: categories,
      loadBudget: loadBudget,
    );
    final controller = FinanceController(
      records: records,
      categories: categories,
      service: service,
      clock: clock,
      initialMonth: initialMonth,
    );
    final budgetController = BudgetController(
      budgets: budgets,
      categories: categories,
      clock: clock,
      initialMonth: initialMonth,
    );

    // 预加载：确保引用检查与首屏渲染读取的是磁盘上的真实数据。
    await categories.list();
    await records.list();
    await budgets.list();

    return FinanceFileScope._(
      categories: categories,
      records: records,
      budgets: budgets,
      service: service,
      controller: controller,
      budgetController: budgetController,
    );
  }

  void dispose() {
    controller.dispose();
    budgetController.dispose();
  }
}
