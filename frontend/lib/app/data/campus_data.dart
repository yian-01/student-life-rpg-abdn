import '../../features/academic/models/course.dart';
import '../../features/academic/controllers/academic_controller.dart';
import '../../features/academic/repositories/assignment_repository.dart';
import '../../features/academic/repositories/exam_repository.dart';
import '../../features/finance/repositories/budget_repository.dart';
import '../../features/finance/repositories/campus_budget_repository.dart';
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
    assignments = AssignmentRepository(store);
    exams = ExamRepository(store);
    budgets = CampusBudgetRepository(store);
    academic = AcademicController(semesters, courses);
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
  late final AssignmentRepository assignments;
  late final ExamRepository exams;
  late final BudgetRepository budgets;
  late final AcademicController academic;
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
