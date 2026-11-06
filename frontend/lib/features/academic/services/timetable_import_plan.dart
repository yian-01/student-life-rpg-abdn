import '../models/course.dart';
import '../models/course_slot.dart';
import 'timetable_import.dart';

/// 单门课程在本次导入中的处置方式。
enum ImportAction {
  /// 本学期没有同名课程，将新建。
  create,

  /// 已有同名课程，只更新上课时段，保留学分与成绩。
  updateSlots,

  /// 已有同名课程且时段完全一致，无需改动。
  unchanged,

  /// 无法导入（例如教务系统未给学分），需要人工修正。
  blocked,
}

/// 预览列表里的一行。
class ImportPlanItem {
  ImportPlanItem({
    required this.parsed,
    required this.action,
    this.existing,
    this.reason,
    bool? selected,
  }) : selected = selected ?? _defaultSelected(action);

  final ParsedCourse parsed;
  final ImportAction action;
  final Course? existing;

  /// 不能导入或被保留的原因，用于界面直接展示。
  final String? reason;

  /// 是否勾选参与导入；默认只有 create / updateSlots 勾选。
  bool selected;

  static bool _defaultSelected(ImportAction action) =>
      action == ImportAction.create || action == ImportAction.updateSlots;

  /// 该条目在给定学分修正下是否会被写入。
  ///
  /// 缺学分的条目补填合法学分后即可导入；`unchanged` 永远不写入。
  bool isWritable(Map<String, double> creditsOverrides) {
    if (action == ImportAction.unchanged) return false;
    if (action == ImportAction.updateSlots) return true;
    final credits = creditsOverrides[parsed.name] ?? parsed.credits;
    return credits != null && credits.isFinite && credits > 0;
  }
}

/// 一次导入的完整计划。
class ImportPlan {
  ImportPlan({required this.semesterId, required this.items});

  final String semesterId;
  final List<ImportPlanItem> items;

  int get createCount =>
      items.where((item) => item.action == ImportAction.create).length;
  int get updateCount =>
      items.where((item) => item.action == ImportAction.updateSlots).length;
  int get unchangedCount =>
      items.where((item) => item.action == ImportAction.unchanged).length;
  int get blockedCount =>
      items.where((item) => item.action == ImportAction.blocked).length;

  /// 实际会被写入的条目（不受预览修正影响）。
  List<ImportPlanItem> get pending => items
      .where((item) => item.selected && item.isWritable(_noOverrides))
      .toList();

  /// 结合预览里补填的学分后，实际会被写入的条目。
  ///
  /// `blocked` 的条目在补填合法学分后可以转为可导入；`unchanged` 永不写入。
  List<ImportPlanItem> pendingWith(Map<String, double> creditsOverrides) =>
      items
          .where((item) => item.selected && item.isWritable(creditsOverrides))
          .toList();

  /// 预览页里显示的一行摘要。
  String get summary =>
      '新增 $createCount 门、更新 $updateCount 门、'
      '无变化 $unchangedCount 门、需修正 $blockedCount 门';
}

const _noOverrides = <String, double>{};

/// 判断两份时段是否等价（用于"无变化"判断）。
bool _sameSlots(List<CourseSlot> a, List<CourseSlot> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].weekday != b[i].weekday) return false;
    if (a[i].startMinute != b[i].startMinute) return false;
    if (a[i].endMinute != b[i].endMinute) return false;
    if (a[i].weeks.length != b[i].weeks.length) return false;
    for (var j = 0; j < b[i].weeks.length; j++) {
      if (a[i].weeks[j] != b[i].weeks[j]) return false;
    }
  }
  return true;
}

/// 把解析结果与目标学期的现有课程比对，生成导入计划。
///
/// 规则（Issue #31）：
/// - 缺学分**不默填 1**，标记为需要修正；
/// - 已有课程保留原学分与成绩，只更新时段，不覆盖手动改动；
/// - 时段完全一致视为无变化，不产生写入；
/// - 缺成绩的课程导入后为"未评分"。
ImportPlan buildImportPlan({
  required TimetableParseResult parsed,
  required List<Course> existingCourses,
  required String semesterId,
  required double scoreScaleMax,
}) {
  final items = <ImportPlanItem>[];
  final seenNames = <String>{};

  for (final course in parsed.courses) {
    final name = course.name.trim();
    if (name.isEmpty) continue;

    if (!seenNames.add(name)) {
      items.add(
        ImportPlanItem(
          parsed: course,
          action: ImportAction.blocked,
          reason: '课表里出现两门同名课程，只导入第一门',
        ),
      );
      continue;
    }

    Course? existing;
    for (final candidate in existingCourses) {
      if (candidate.semesterId != semesterId) continue;
      if (candidate.name.trim() != name) continue;
      existing = candidate;
      break;
    }

    final newSlots = [
      for (final slot in course.slots)
        CourseSlot(
          weekday: slot.weekday,
          startMinute: slot.startMinute,
          endMinute: slot.endMinute,
          weeks: slot.weeks,
        ),
    ];

    if (existing != null) {
      final same = _sameSlots(existing.slots, newSlots);
      items.add(
        ImportPlanItem(
          parsed: course,
          action: same ? ImportAction.unchanged : ImportAction.updateSlots,
          existing: existing,
          reason: same ? '时段与已有课程一致' : '将替换为 ${newSlots.length} 个时段，保留原学分与成绩',
        ),
      );
      continue;
    }

    if (course.credits == null) {
      items.add(
        ImportPlanItem(
          parsed: course,
          action: ImportAction.blocked,
          reason: '教务系统没有给出学分，请在预览里补填后再导入',
        ),
      );
      continue;
    }

    items.add(
      ImportPlanItem(
        parsed: course,
        action: ImportAction.create,
        reason: '新增 ${newSlots.length} 个时段',
      ),
    );
  }

  return ImportPlan(semesterId: semesterId, items: items);
}

/// 计划里将要写入的课程（已套用到领域模型）。
///
/// [creditsOverrides] 允许预览页修正学分；键为课程名。
List<Course> coursesFromPlan(
  ImportPlan plan, {
  required double scoreScaleMax,
  Map<String, double> creditsOverrides = const {},
  String idPrefix = 'imported',
}) {
  final result = <Course>[];
  var index = 0;
  for (final item in plan.pendingWith(creditsOverrides)) {
    index++;
    final base = item.existing;
    // 已有课程保留原学分（可能是用户手动改过的），只有新课程才用导入值；
    // 预览里的显式修正优先。
    final credits =
        creditsOverrides[item.parsed.name] ??
        base?.credits ??
        item.parsed.credits;
    if (credits == null || !credits.isFinite || credits <= 0) continue;
    final slots = [
      for (final slot in item.parsed.slots)
        CourseSlot(
          weekday: slot.weekday,
          startMinute: slot.startMinute,
          endMinute: slot.endMinute,
          weeks: slot.weeks,
        ),
    ];
    result.add(
      Course(
        id:
            base?.id ??
            '$idPrefix-$index-${item.parsed.classCode.hashCode.abs()}',
        semesterId: plan.semesterId,
        name: item.parsed.name,
        credits: credits,
        // 已有成绩与手动改动不被导入覆盖。
        gradePoint: base?.gradePoint,
        slots: slots,
        scoreScaleMax: scoreScaleMax,
      ),
    );
  }
  return result;
}
