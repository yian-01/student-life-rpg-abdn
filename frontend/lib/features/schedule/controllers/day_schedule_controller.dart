import 'package:flutter/foundation.dart';

import '../services/day_schedule_service.dart';

/// 单日日程 Controller：负责日期切换、加载、错误与请求防串扰。
class DayScheduleController extends ChangeNotifier {
  DayScheduleController({required this.loader, DateTime? initialDate})
    : _selectedDate = _normalizeDate(initialDate ?? DateTime.now());

  final DayScheduleLoader loader;
  DateTime _selectedDate;
  DaySchedule? _schedule;
  bool _isLoading = false;
  String? _errorMessage;
  int _requestId = 0;
  bool _disposed = false;

  DateTime get selectedDate => _selectedDate;
  DaySchedule? get schedule => _schedule;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadDay([DateTime? date]) async {
    final target = date == null ? _selectedDate : _normalizeDate(date);
    final dateChanged =
        target.year != _selectedDate.year ||
        target.month != _selectedDate.month ||
        target.day != _selectedDate.day;
    _selectedDate = target;
    if (dateChanged) {
      _schedule = null;
    }

    final requestId = ++_requestId;
    _isLoading = true;
    _errorMessage = null;
    _notifyIfActive();

    try {
      final result = await loader.loadDay(target);
      if (_disposed || requestId != _requestId) {
        return;
      }
      _schedule = result;
    } catch (_) {
      if (_disposed || requestId != _requestId) {
        return;
      }
      _schedule = null;
      _errorMessage = '日程加载失败，请重试。';
    } finally {
      if (!_disposed && requestId == _requestId) {
        _isLoading = false;
        _notifyIfActive();
      }
    }
  }

  Future<void> retry() => loadDay();

  Future<void> goToPreviousDay() {
    return loadDay(
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day - 1),
    );
  }

  Future<void> goToNextDay() {
    return loadDay(
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day + 1),
    );
  }

  void _notifyIfActive() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

DateTime _normalizeDate(DateTime date) {
  if (date.isUtc) {
    throw ArgumentError.value(date, 'date', 'must be local civil time');
  }
  return DateTime(date.year, date.month, date.day);
}
