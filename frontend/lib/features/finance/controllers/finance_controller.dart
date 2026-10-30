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
  Object? _error;
  MonthlyFinanceSummary? _summary;
  List<FinanceRecord> _monthRecords = const [];
  List<FinanceCategory> _availableCategories = const [];
  int _loadToken = 0;
  int _recordSeq = 0;
  bool _disposed = false;

  DateTime get month => _month;
  bool get isLoading => _isLoading;
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

  Future<void> addRecord({
    required String categoryId,
    required String amountText,
    String? note,
  }) async {
    if (_disposed) return;
    try {
      final category = await _categories.getById(categoryId);
      if (_disposed) return;
      if (category == null) {
        _fail(StateError('Unknown finance category: $categoryId'));
        return;
      }

      final amountMinor = parseAmountMinor(amountText);

      final now = _clock();
      requireLocalDateTime(now, 'now');
      _recordSeq += 1;
      final record = FinanceRecord(
        id: 'rec-${now.microsecondsSinceEpoch}-$_recordSeq',
        categoryId: category.id,
        type: category.type,
        amountMinor: amountMinor,
        occurredAt: now,
        note: note == null || note.trim().isEmpty ? null : note,
      );

      await _records.insert(record);
    } catch (error) {
      _fail(error);
      return;
    }

    await _loadCurrent();
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
