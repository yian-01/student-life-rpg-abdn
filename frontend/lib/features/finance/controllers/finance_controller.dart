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

  DateTime get month => _month;
  bool get isLoading => _isLoading;
  Object? get error => _error;
  MonthlyFinanceSummary? get summary => _summary;
  List<FinanceRecord> get monthRecords => _monthRecords;
  List<FinanceCategory> get availableCategories => _availableCategories;
  List<String> get diagnostics => _service.diagnostics;

  Future<void> load({DateTime? month}) async {
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
    final category = await _categories.getById(categoryId);
    if (category == null) {
      _error = StateError('Unknown finance category: $categoryId');
      notifyListeners();
      return;
    }

    late final int amountMinor;
    try {
      amountMinor = parseAmountMinor(amountText);
    } catch (error) {
      _error = error;
      notifyListeners();
      return;
    }

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

    try {
      await _records.insert(record);
    } catch (error) {
      _error = error;
      notifyListeners();
      return;
    }

    await _loadCurrent();
  }

  List<FinanceCategory> categoriesFor(FinanceType type) {
    return _availableCategories
        .where((category) => category.type == type)
        .toList();
  }

  Future<void> _loadCurrent() async {
    final token = ++_loadToken;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final summary = await _service.loadMonth(_month);
      final categories = await _categories.list();
      final monthRecords =
          (await _records.list())
              .where(
                (record) =>
                    !record.occurredAt.isBefore(_month) &&
                    record.occurredAt.isBefore(
                      DateTime(_month.year, _month.month + 1),
                    ),
              )
              .toList()
            ..sort((a, b) {
              final byTime = a.occurredAt.compareTo(b.occurredAt);
              return byTime != 0 ? byTime : a.id.compareTo(b.id);
            });

      if (token != _loadToken) {
        return;
      }
      _summary = summary;
      _availableCategories = categories;
      _monthRecords = monthRecords;
      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (error) {
      if (token != _loadToken) {
        return;
      }
      _isLoading = false;
      _error = error;
      notifyListeners();
    }
  }
}
