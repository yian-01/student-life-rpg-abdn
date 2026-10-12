import 'package:flutter/foundation.dart';

import '../../../shared/repositories/entity_repository.dart';
import '../../academic/models/course.dart';
import '../models/gpa_result.dart';
import '../services/gpa_calculator.dart';

class GpaController extends ChangeNotifier {
  GpaController({required this.courseRepository, required this.scoreScaleMax}) {
    if (!scoreScaleMax.isFinite || scoreScaleMax <= 0) {
      throw ArgumentError.value(scoreScaleMax, 'scoreScaleMax');
    }
  }

  final EntityRepository<Course> courseRepository;
  final double scoreScaleMax;
  final _calculator = GpaCalculator();
  GpaResult? _result;
  Object? _error;
  bool _isLoading = false;
  bool _disposed = false;
  int _request = 0;
  String? _semesterId;
  List<Course> _allCourses = const [];
  List<Course> _courses = const [];

  GpaResult? get result => _result;
  Object? get error => _error;
  bool get isLoading => _isLoading;
  String? get semesterId => _semesterId;
  List<Course> get courses => _courses;
  List<String> get semesterIds => List.unmodifiable(
    _allCourses.map((c) => c.semesterId).toSet().toList()..sort(),
  );

  Future<void> load({String? semesterId}) async {
    if (_disposed) return;
    final request = ++_request;
    _semesterId = semesterId;
    _begin();
    try {
      if (semesterId != null && semesterId.trim().isEmpty) {
        throw ArgumentError.value(semesterId, 'semesterId');
      }
      final all = await courseRepository.list();
      final selected = all
          .where((c) => semesterId == null || c.semesterId == semesterId)
          .toList();
      final result = _calculator.calculate(
        selected,
        scoreScaleMax: scoreScaleMax,
      );
      if (_disposed || request != _request) return;
      _allCourses = List.unmodifiable(all);
      _courses = List.unmodifiable(selected);
      _result = result;
    } catch (error) {
      if (_disposed || request != _request) return;
      _error = error;
    } finally {
      _finish(request);
    }
  }

  Future<void> retry() => load(semesterId: _semesterId);

  /// Write through the same repository used for reads and refresh the selection.
  /// Errors remain visible and are never disguised as successful empty data.
  Future<void> setGradePoint(String id, double? gradePoint) async {
    if (_disposed || _isLoading) return;
    final request = ++_request;
    _begin();
    try {
      final course = await courseRepository.getById(id);
      if (course == null) throw StateError('Unknown course: $id');
      await courseRepository.update(
        Course(
          id: course.id,
          semesterId: course.semesterId,
          name: course.name,
          credits: course.credits,
          gradePoint: gradePoint,
          slots: course.slots,
          scoreScaleMax: scoreScaleMax,
        ),
      );
      if (!_disposed && request == _request) {
        await load(semesterId: _semesterId);
      }
    } catch (error) {
      if (!_disposed && request == _request) _error = error;
    } finally {
      _finish(request);
    }
  }

  void _begin() {
    _isLoading = true;
    _error = null;
    _result = null;
    notifyListeners();
  }

  void _finish(int request) {
    if (!_disposed && request == _request) {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
