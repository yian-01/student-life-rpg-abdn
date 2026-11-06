import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/academic/models/semester.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

class MemoryCampusDocuments implements JsonDocumentStore {
  final documents = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> readDocument(String path) async => documents[path];
  @override
  Future<void> writeDocument(String path, String content) async {
    if (failWrites) throw StateError('Injected disk failure');
    if (documents.containsKey(path)) documents['$path.bak'] = documents[path]!;
    documents[path] = content;
  }
}

CampusData emptyCampusData() =>
    CampusData(CampusStore(MemoryCampusDocuments(), 'campus.json'));

/// 带一个学期与一门课程的 CampusData。
///
/// 作业/考试的 `courseId` 受引用完整性约束，导入与课程测试也需要
/// 先有学期可以挂靠，因此统一用这个夹具，不再另造替身。
Future<CampusData> campusWithCourse({String courseId = 'c1'}) async {
  final data = emptyCampusData();
  await data.semesters.insert(
    Semester(
      id: 's1',
      name: '测试学期',
      startDate: DateTime(2026, 10, 26),
      endDate: DateTime(2026, 11, 29),
      week1Monday: DateTime(2026, 10, 26),
    ),
  );
  await data.courses.insert(
    Course(
      id: courseId,
      semesterId: 's1',
      name: '线性代数',
      credits: 2,
      scoreScaleMax: 4,
      slots: const [],
    ),
  );
  return data;
}
