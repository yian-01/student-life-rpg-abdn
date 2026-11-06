import '../../../app/data/campus_store.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../models/exam.dart';

/// 考试仓库。
///
/// 正式应用由组合根注入持久化实现（`StoredExamRepository`）。
abstract interface class ExamRepository implements EntityRepository<Exam> {
  /// 该课程下的考试，按 [Exam.range] 起点升序（同时间按 id 稳定排序）。
  Future<List<Exam>> listForCourse(String courseId);
}

/// Persistent implementation shared by application pages and services.
class StoredExamRepository extends CampusRepository<Exam>
    implements ExamRepository {
  StoredExamRepository(CampusStore store)
    : super(store, 'exams', Exam.fromJson, (v) => v.toJson());
  @override
  Future<List<Exam>> listForCourse(String courseId) async {
    if (courseId.trim().isEmpty) {
      throw ArgumentError.value(courseId, 'courseId');
    }
    final rows =
        (await list()).where((row) => row.courseId == courseId).toList()
          ..sort((a, b) {
            final byTime = a.range.start.compareTo(b.range.start);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    return List.unmodifiable(rows);
  }
}
