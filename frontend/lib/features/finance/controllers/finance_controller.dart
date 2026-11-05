// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../../shared/repositories/entity_repository.dart';
import '../models/finance_category.dart';
import '../models/finance_record.dart';
import '../models/finance_type.dart';
import '../models/local_date_time_json.dart';
import '../models/money.dart';
import '../models/monthly_finance_summary.dart';
import '../services/finance_summary_service.dart';

class FinanceController extends ChangeNotifier {
  FinanceController({
    required EntityRepository<FinanceRecord> records,
    required EntityRepository<FinanceCategory> categories,
    required FinanceSummaryService service,
    DateTime Function()? clock,
    DateTime? initialMonth,
  }) : _records = records,
       _categories = categories,
       _service = service,
       _clock = clock ?? DateTime.now {
    final now = _clock();
    requireLocalDateTime(now, 'now');
    _month = initialMonth == null
        ? DateTime(now.year, now.month)
        : DateTime(initialMonth.year, initialMonth.month);
  }

  final EntityRepository<FinanceRecord> _records;
  final EntityRepository<FinanceCategory> _categories;
  final FinanceSummaryService _service;
  final DateTime Function() _clock;

  late DateTime _month;
  bool _isLoading = false;
  bool _isSaving = false;
  Object? _error;
  MonthlyFinanceSummary? _summary;
  List<FinanceRecord> _monthRecords = const [];
  List<FinanceCategory> _availableCategories = const [];
  int _loadToken = 0;
  int _recordSeq = 0;
  int _categorySeq = 0;
  bool _disposed = false;

  DateTime get month => _month;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  Object? get error => _error;
  MonthlyFinanceSummary? get summary => _summary;
  List<FinanceRecord> get monthRecords => _monthRecords;
  List<FinanceCategory> get availableCategories => _availableCategories;
  List<String> get diagnostics => _service.diagnostics;

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

  Future<bool> addRecord({
    required String categoryId,
    required String amountText,
    String? note,
  }) => _write(() async {
    final category = await _categories.getById(categoryId);
    if (category == null) throw StateError('Unknown finance category');
    final now = _clock();
    requireLocalDateTime(now, 'now');
    _recordSeq++;
    await _records.insert(
      FinanceRecord(
        id: 'rec-${now.microsecondsSinceEpoch}-$_recordSeq',
        categoryId: category.id,
        type: category.type,
        amountMinor: parseAmountMinor(amountText),
        occurredAt: now,
        note: note == null || note.trim().isEmpty ? null : note.trim(),
      ),
    );
  });

  Future<bool> updateRecord(
    String id, {
    required String categoryId,
    required String amountText,
    required DateTime occurredAt,
    String? note,
  }) => _write(() async {
    final existing = await _records.getById(id);
    final category = await _categories.getById(categoryId);
    if (existing == null || category == null) {
      throw StateError('Unknown record/category');
    }
    await _records.update(
      existing.copyWith(
        categoryId: category.id,
        type: category.type,
        amountMinor: parseAmountMinor(amountText),
        occurredAt: occurredAt,
        note: note == null || note.trim().isEmpty ? null : note.trim(),
      ),
    );
  });

  Future<bool> removeRecord(String id) => _write(() async {
    if (!await _records.remove(id)) throw StateError('Unknown record');
  });

  /// 新增分类。空白名称由模型抛出 ArgumentError；同类型下同名分类被拒绝。
  Future<bool> addCategory({required String name, required FinanceType type}) =>
      _write(() async {
        final now = _clock();
        requireLocalDateTime(now, 'now');
        _categorySeq++;
        await _categories.insert(
          FinanceCategory(
            id: 'cat-${now.microsecondsSinceEpoch}-$_categorySeq',
            name: name,
            type: type,
          ),
        );
      });

  /// 编辑分类名称/类型。被记录或预算引用时无法修改类型，会抛出带原因的 StateError。
  Future<bool> editCategory(
    String id, {
    required String name,
    required FinanceType type,
  }) => _write(() async {
    final existing = await _categories.getById(id);
    if (existing == null) throw StateError('未知分类。');
    await _categories.update(
      FinanceCategory(id: existing.id, name: name, type: type),
    );
  });

  /// 删除分类。被记录或预算引用时阻止删除并说明原因。
  Future<bool> deleteCategory(String id) => _write(() async {
    if (!await _categories.remove(id)) throw StateError('未知分类。');
  });

  Future<bool> _write(Future<void> Function() action) async {
    if (_disposed || _isSaving) return false;
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      await _loadCurrent();
      // A refresh error is displayed, but cannot turn a committed write into a
      // retryable insert: the form must clear after a successful disk commit.
      return true;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _isSaving = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _fail(Object error) {
    if (_disposed) return;
    _error = error;
    notifyListeners();
  }

  List<FinanceCategory> categoriesFor(FinanceType type) {
    return _availableCategories
        .where((category) => category.type == type)
        .toList();
  }

  Future<void> _loadCurrent() async {
    if (_disposed) return;
    final requestedMonth = _month;
    final token = ++_loadToken;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final summary = await _service.loadMonth(requestedMonth);
      final categories = await _categories.list();
      final monthRecords =
          (await _records.list())
              .where(
                (record) =>
                    !record.occurredAt.isBefore(requestedMonth) &&
                    record.occurredAt.isBefore(
                      DateTime(requestedMonth.year, requestedMonth.month + 1),
                    ),
              )
              .toList()
            ..sort((a, b) {
              final byTime = a.occurredAt.compareTo(b.occurredAt);
              return byTime != 0 ? byTime : a.id.compareTo(b.id);
            });

      if (_disposed || token != _loadToken) {
        return;
      }
      _summary = summary;
      _availableCategories = List.unmodifiable(categories);
      _monthRecords = List.unmodifiable(monthRecords);
      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (error) {
      if (_disposed || token != _loadToken) {
        return;
      }
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
