import 'package:flutter/foundation.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../models/course.dart';
import '../models/semester.dart';

class AcademicController extends ChangeNotifier {
  AcademicController(this._semesters, this._courses);
  final EntityRepository<Semester> _semesters;
  final EntityRepository<Course> _courses;
  List<Semester> _loadedSemesters = const [];
  List<Course> _loadedCourses = const [];
  List<Semester> get semesters => _loadedSemesters;
  List<Course> get courses => _loadedCourses;
  bool _disposed = false;
  Future<void> load() async {
    final terms = await _semesters.list();
    final subjects = await _courses.list();
    if (_disposed) return;
    _loadedSemesters = List.unmodifiable(terms);
    _loadedCourses = List.unmodifiable(subjects);
    notifyListeners();
  }

  Future<void> saveSemester(Semester value, {required bool creating}) =>
      creating ? _semesters.insert(value) : _semesters.update(value);
  Future<void> saveCourse(Course value, {required bool creating}) =>
      creating ? _courses.insert(value) : _courses.update(value);
  Future<void> removeSemester(String id) async {
    if (!await _semesters.remove(id)) throw StateError('Unknown semester');
  }

  Future<void> removeCourse(String id) async {
    if (!await _courses.remove(id)) throw StateError('Unknown course');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
