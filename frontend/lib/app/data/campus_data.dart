import '../../features/academic/models/course.dart';
import '../../features/academic/controllers/academic_controller.dart';
import '../../features/academic/repositories/assignment_repository.dart';
import '../../features/academic/repositories/exam_repository.dart';
import '../../features/schedule/controllers/event_controller.dart';
import '../../features/academic/models/semester.dart';
import '../../features/academic/services/course_occurrence_service.dart';
import '../../features/finance/controllers/finance_controller.dart';
import '../../features/finance/models/finance_category.dart';
import '../../features/finance/models/finance_record.dart';
import '../../features/finance/services/finance_summary_service.dart';
import '../../features/gpa/composition/gpa_composition.dart';
import '../../features/schedule/composition/schedule_composition.dart';
import '../../features/schedule/models/event.dart';
import '../../features/schedule/repositories/task_repository.dart';
import '../../shared/models/schedule_item.dart';
import 'campus_store.dart';

class CampusData {
  CampusData(this.store) {
    semesters = CampusRepository(
      store,
      'semesters',
      Semester.fromJson,
      (v) => v.toJson(),
    );
    courses = CampusRepository(
      store,
      'courses',
      (v) => Course.fromJson(v, scoreScaleMax: CampusStore.scoreScaleMax),
      (v) => v.toJson(),
    );
    events = CampusRepository(
      store,
      'events',
      Event.fromJson,
      (v) => v.toJson(),
    );
    categories = CampusRepository(
      store,
      'categories',
      FinanceCategory.fromJson,
      (v) => v.toJson(),
    );
    records = CampusRepository(
      store,
      'records',
      FinanceRecord.fromJson,
      (v) => v.toJson(),
    );
    academic = AcademicController(semesters, courses);
    // 作业/考试当前使用内存仓库：CampusStore 的文档要求固定 8 个顶层键，
    // 新增表属于共享持久化扩展，由李雨真（#30）接入；
    // 在此之前不另建独立数据源，也不把内存实现当作持久化证据。
    assignments = InMemoryAssignmentRepository();
    exams = InMemoryExamRepository();
    eventController = EventController(events);
    gpa = GpaComposition(
      courseRepository: courses,
      semesterRepository: semesters,
      scoreScaleMax: CampusStore.scoreScaleMax,
    );
    financeService = FinanceSummaryService(
      records: records,
      categories: categories,
      loadBudget: (_) async => null,
    );
    finance = FinanceController(
      records: records,
      categories: categories,
      service: financeService,
    );
  }
  final CampusStore store;
  late final CampusRepository<Semester> semesters;
  late final CampusRepository<Course> courses;
  late final CampusRepository<Event> events;
  late final CampusRepository<FinanceCategory> categories;
  late final CampusRepository<FinanceRecord> records;
  late final AcademicController academic;
  late final AssignmentRepository assignments;
  late final ExamRepository exams;
  late final EventController eventController;
  late final GpaComposition gpa;
  late final FinanceSummaryService financeService;
  late final FinanceController finance;

  ScheduleComposition schedule(TaskRepository tasks) => ScheduleComposition(
    taskRepository: tasks,
    eventRepository: events,
    courseOccurrencesForDate: courseOccurrences,
  );

  Future<List<ScheduleItem>> courseOccurrences(DateTime date) async {
    final snapshot = await store.snapshot();
    final semesterRows = (snapshot['semesters'] as List)
        .cast<Map<String, dynamic>>();
    final courseRows = (snapshot['courses'] as List)
        .cast<Map<String, dynamic>>();
    final byId = {
      for (final row in semesterRows)
        row['id'] as String: Semester.fromJson(row),
    };
    final result = <ScheduleItem>[];
    for (final row in courseRows) {
      final course = Course.fromJson(
        row,
        scoreScaleMax: CampusStore.scoreScaleMax,
      );
      final semester = byId[course.semesterId];
      if (semester == null) {
        throw StateError('Missing semester ${course.semesterId}');
      }
      result.addAll(occurrencesForDate(course, semester, date));
    }
    return result;
  }

  void dispose() {
    finance.dispose();
    academic.dispose();
    eventController.dispose();
  }
}
