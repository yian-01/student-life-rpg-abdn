import '../../../shared/repositories/entity_repository.dart';
import '../../academic/models/course.dart';
import '../../academic/models/course_slot.dart';
import '../../academic/models/semester.dart';
import '../../academic/repositories/course_repository.dart';
import '../../academic/repositories/semester_repository.dart';
import '../controllers/gpa_controller.dart';
import '../models/gpa_result.dart';
import '../services/gpa_calculator.dart';

/// A owns this assembly and shares [courseRepository] with academic consumers.
class GpaComposition {
  GpaComposition({
    required this.courseRepository,
    required this.scoreScaleMax,
    this.isDemo = false,
    Future<void>? ready,
  }) : _ready = ready ?? Future.value() {
    if (!scoreScaleMax.isFinite || scoreScaleMax <= 0) {
      throw ArgumentError.value(scoreScaleMax, 'scoreScaleMax');
    }
  }

  final EntityRepository<Course> courseRepository;
  final double scoreScaleMax;
  final bool isDemo;
  Future<void>? _ready;

  Future<GpaController> createController() async {
    if (_ready case final ready?) {
      await ready;
      _ready = null;
    }
    return GpaController(
      courseRepository: courseRepository,
      scoreScaleMax: scoreScaleMax,
    );
  }

  /// Directly injectable into DashboardService.loadGpa; no duplicate formula.
  Future<GpaResult> loadGpa({String? semesterId}) async {
    if (_ready case final ready?) {
      await ready;
      _ready = null;
    }
    if (semesterId != null && semesterId.trim().isEmpty) {
      throw ArgumentError.value(semesterId, 'semesterId');
    }
    final courses = await courseRepository.list();
    return GpaCalculator().calculate(
      courses
          .where((c) => semesterId == null || c.semesterId == semesterId)
          .toList(),
      scoreScaleMax: scoreScaleMax,
    );
  }

  /// Explicit synthetic demo using G's real repositories and reference checks.
  factory GpaComposition.inMemoryDemo() {
    late final InMemoryCourseRepository courses;
    final semesters = InMemorySemesterRepository(
      isReferenced: (id) => courses.hasCoursesForSemester(id),
    );
    courses = InMemoryCourseRepository(semesterExists: semesters.exists);
    Future<void> seed() async {
      for (final id in ['2026秋季', '2027春季']) {
        await semesters.insert(
          Semester(
            id: id,
            name: '$id（演示）',
            startDate: DateTime(2026, 10, 5),
            endDate: DateTime(2027, 6, 30),
            week1Monday: DateTime(2026, 10, 5),
          ),
        );
      }
      final slot = CourseSlot(
        weekday: 1,
        startMinute: 540,
        endMinute: 600,
        weeks: [1, 2, 3],
      );
      for (final course in [
        Course(
          id: 'demo-math',
          semesterId: '2026秋季',
          name: '数学（合成数据）',
          credits: 5,
          gradePoint: 3.7,
          slots: [slot],
          scoreScaleMax: 4,
        ),
        Course(
          id: 'demo-english',
          semesterId: '2026秋季',
          name: '英语（合成数据）',
          credits: 3,
          slots: [slot],
          scoreScaleMax: 4,
        ),
        Course(
          id: 'demo-zero',
          semesterId: '2027春季',
          name: '编程（零绩点演示）',
          credits: 2,
          gradePoint: 0,
          slots: [slot],
          scoreScaleMax: 4,
        ),
      ]) {
        await courses.insert(course);
      }
    }

    return GpaComposition(
      courseRepository: courses,
      scoreScaleMax: 4,
      isDemo: true,
      ready: seed(),
    );
  }
}
