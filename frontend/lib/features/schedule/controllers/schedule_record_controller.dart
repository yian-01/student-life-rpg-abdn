import 'package:flutter/foundation.dart';
import '../../../shared/repositories/entity_repository.dart';

/// Reads/deletes the original entity; a schedule row is never a second record.
class ScheduleRecordController<T> extends ChangeNotifier {
  ScheduleRecordController({required this.repository, required this.id});
  final EntityRepository<T> repository;
  final String id;
  T? record;
  bool isLoading = false;
  bool isDeleting = false;
  String? error;
  bool _disposed = false;
  int _request = 0;

  Future<void> load() async {
    final request = ++_request;
    isLoading = true;
    error = null;
    _notify();
    try {
      final value = await repository.getById(id);
      if (_disposed || request != _request) return;
      record = value;
      if (value == null) error = '该记录已删除，请返回日程刷新。';
    } catch (_) {
      if (_disposed || request != _request) return;
      error = '详情读取失败，请重试。';
    } finally {
      if (!_disposed && request == _request) {
        isLoading = false;
        _notify();
      }
    }
  }

  Future<bool> remove() async {
    if (isDeleting) return false;
    isDeleting = true;
    error = null;
    _notify();
    try {
      await repository.remove(id);
      return true;
    } catch (_) {
      if (!_disposed) error = '删除失败，记录已保留，请重试。';
      return false;
    } finally {
      isDeleting = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
