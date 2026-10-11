import 'package:flutter/foundation.dart';

import '../../../shared/models/time_range.dart';
import '../models/task.dart';
import '../repositories/task_repository.dart';
import '../services/day_schedule_service.dart';

/// 新建 Task 的 ID 生成器；默认按微秒时间戳生成，测试可注入确定性实现。
typedef TaskIdGenerator = String Function();

/// 单日日程 Controller：负责日期切换、加载、错误与请求防串扰。
class DayScheduleController extends ChangeNotifier {
  DayScheduleController({
    required this.loader,
    this.taskRepository,
    this.demoData = false,
    TaskIdGenerator? idGenerator,
    DateTime? initialDate,
  }) : _idGenerator = idGenerator ?? _defaultTaskIdGenerator,
       _selectedDate = _normalizeDate(initialDate ?? DateTime.now());

  final DayScheduleLoader loader;
  final TaskRepository? taskRepository;

  /// 是否为内存演示装配；为 true 时页面显示“仅存内存”提示。
  final bool demoData;
  final TaskIdGenerator _idGenerator;
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

  /// 只有注入 [TaskRepository] 时才允许新增任务与切换完成状态。
  bool get canEditTasks => taskRepository != null;

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

  /// 新增一个最小 Task 并刷新当前日期。
  ///
  /// 入参非法时抛 [ArgumentError]（页面提示表单错误）；未注入仓库时抛
  /// [StateError]；仓库写入失败保留原始异常，由调用方给出可见反馈。
  Future<void> addTask({
    required String title,
    required int estimatedMinutes,
    DateTime? dueAt,
    TimeRange? scheduledRange,
  }) async {
    final repository = taskRepository;
    if (repository == null) {
      throw StateError('TaskRepository is not injected');
    }

    final task = Task(
      id: _idGenerator(),
      title: title,
      estimatedMinutes: estimatedMinutes,
      dueAt: dueAt,
      scheduledRange: scheduledRange,
    );

    await repository.insert(task);
    await loadDay();
  }

  /// 设置任务完成状态并刷新当前日期；未知 ID 由仓库抛出 [StateError]。
  Future<void> setTaskCompleted(String taskId, bool isCompleted) async {
    final repository = taskRepository;
    if (repository == null) {
      throw StateError('TaskRepository is not injected');
    }

    await repository.setCompleted(taskId, isCompleted);
    await loadDay();
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

String _defaultTaskIdGenerator() {
  return 'task-${DateTime.now().microsecondsSinceEpoch}';
}
