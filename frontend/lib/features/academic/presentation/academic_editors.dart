import 'package:flutter/material.dart';
import '../../../app/data/campus_data.dart';
import '../../../app/data/campus_store.dart';
import '../../../shared/presentation/civil_datetime_field.dart';
import '../../../shared/presentation/record_editor_dialog.dart';
import '../models/course.dart';
import '../models/course_slot.dart';
import '../models/semester.dart';
import '../services/semester_week_guard.dart';

class SemesterEditor extends StatefulWidget {
  const SemesterEditor({
    super.key,
    required this.data,
    this.semester,
    this.courses = const [],
  });
  final CampusData data;
  final Semester? semester;

  /// 该学期下的课程，用于在缩短学期时检查已有时段是否越界。
  final List<Course> courses;
  @override
  State<SemesterEditor> createState() => _SemesterEditorState();
}

class _SemesterEditorState extends State<SemesterEditor> {
  late final _name = TextEditingController(text: widget.semester?.name ?? '');
  late DateTime _start =
      widget.semester?.startDate ?? DateUtils.dateOnly(DateTime.now());
  late DateTime _end =
      widget.semester?.endDate ??
      DateTime(_start.year, _start.month, _start.day + 120);
  late DateTime _monday =
      widget.semester?.week1Monday ??
      DateTime(_start.year, _start.month, _start.day - _start.weekday + 1);
  late final _id =
      widget.semester?.id ??
      'semester-${DateTime.now().microsecondsSinceEpoch}';
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) throw const FormatException('学期名称不能为空');
    if (_start.isAfter(_end)) throw const FormatException('学期结束日期不能早于开始日期');
    if (_monday.weekday != DateTime.monday) {
      throw const FormatException('第 1 周起点必须选择周一');
    }
    final value = Semester(
      id: _id,
      name: _name.text.trim(),
      startDate: _start,
      endDate: _end,
      week1Monday: _monday,
    );

    // 缩短学期或改锚点会让已有时段的周次越界。此时直接阻止保存，
    // 并点名受影响的课程，不做静默截断或删除。
    final affected = coursesOutsideSemesterWeeks(value, widget.courses);
    if (affected.isNotEmpty) {
      final scope = value.hasSchedulableWeeks
          ? '新学期最多只有 1–${value.lastValidWeek} 周'
          : '按当前日期该学期没有可用周次';
      throw FormatException(
        '$scope，但有 ${affected.length} 门课程的上课时段超出该范围：'
        '${affected.join('、')}。请先调整这些课程的周次后重试，未做任何修改。',
      );
    }

    await widget.data.academic.saveSemester(
      value,
      creating: widget.semester == null,
    );
  }

  @override
  Widget build(BuildContext context) => RecordEditorDialog(
    title: widget.semester == null ? '新建学期' : '编辑学期',
    onSave: _save,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('semester-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: '学期名称'),
        ),
        const SizedBox(height: 12),
        CivilDateTimeField(
          label: '开始日期',
          value: _start,
          enabled: true,
          showTime: false,
          onChanged: (v) => setState(() => _start = v),
        ),
        CivilDateTimeField(
          label: '结束日期',
          value: _end,
          enabled: true,
          showTime: false,
          onChanged: (v) => setState(() => _end = v),
        ),
        CivilDateTimeField(
          label: '第 1 周周一',
          value: _monday,
          enabled: true,
          showTime: false,
          onChanged: (v) => setState(() => _monday = v),
        ),
      ],
    ),
  );
}

/// Accepted grammar: `1-16`、`1,3,5`、`1-16单`、`1-16双`、`1-16(单)`；
/// 拒绝重复、倒序、越界与超出学期的周次。
///
/// [maxWeek] 为所选学期的最后合法周次（[Semester.lastValidWeek]）。
/// 给出时，任何超过它的周次都会被拒绝——五周学期不可能接受 1-999。
/// 为 null 时只做结构校验，仍保留 1000 这个绝对上限，防止明显荒谬的输入。
List<int> parseCourseWeeks(String text, {int? maxWeek}) {
  final weeks = <int>{};
  for (final part in text.replaceAll('，', ',').split(',')) {
    final match = RegExp(
      r'^\s*(\d+)(?:\s*-\s*(\d+))?\s*(?:[（(]?\s*([单双])\s*[)）]?)?\s*$',
    ).firstMatch(part);
    if (match == null) {
      throw const FormatException('周次格式应为 1-16、1,3,5 或 1-16单/双');
    }
    final start = int.parse(match[1]!);
    final end = int.parse(match[2] ?? match[1]!);
    if (start < 1 || end < start || end > 1000) {
      throw const FormatException('周次须为 1–1000，范围不能倒序');
    }
    final limit = maxWeek;
    if (limit != null) {
      if (limit < 1) {
        throw const FormatException('所选学期没有可排课的周次，请先检查学期日期');
      }
      if (end > limit) {
        throw FormatException('本学期只有 1–$limit 周，周次不能超过 $limit');
      }
    }
    final parity = match[3];
    var added = 0;
    for (var i = start; i <= end; i++) {
      if (parity == '单' && i.isEven) continue;
      if (parity == '双' && i.isOdd) continue;
      if (!weeks.add(i)) throw const FormatException('周次不能重复');
      added++;
    }
    if (added == 0) {
      throw FormatException('第 $start–$end 周里没有$parity周，请检查周次写法');
    }
  }
  return weeks.toList()..sort();
}

int parseCourseMinute(String text, {bool allowMidnight = false}) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (m == null) throw const FormatException('时间格式应为 HH:mm');
  final hour = int.parse(m[1]!);
  final minute = int.parse(m[2]!);
  if (hour == 24 && minute == 0 && allowMidnight) return 1440;
  if (hour > 23 || minute > 59) throw const FormatException('请输入有效的时和分');
  return hour * 60 + minute;
}

class _SlotDraft {
  _SlotDraft([CourseSlot? slot, String? defaultWeeksText])
    : weekday = slot?.weekday ?? 1,
      start = TextEditingController(text: _time(slot?.startMinute ?? 540)),
      end = TextEditingController(text: _time(slot?.endMinute ?? 600)),
      weeks = TextEditingController(
        text: slot != null
            ? slot.weeks.join(',')
            : (defaultWeeksText ?? '1-16'),
      );
  int weekday;
  final TextEditingController start, end, weeks;
  CourseSlot build({int? maxWeek}) {
    final a = parseCourseMinute(start.text);
    final b = parseCourseMinute(end.text, allowMidnight: true);
    if (a >= b) throw const FormatException('课程结束时间必须晚于开始时间');
    return CourseSlot(
      weekday: weekday,
      startMinute: a,
      endMinute: b,
      weeks: parseCourseWeeks(weeks.text, maxWeek: maxWeek),
    );
  }

  void dispose() {
    start.dispose();
    end.dispose();
    weeks.dispose();
  }
}

String _time(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

class CourseEditor extends StatefulWidget {
  const CourseEditor({
    super.key,
    required this.data,
    required this.semesters,
    this.course,
  });
  final CampusData data;
  final List<Semester> semesters;
  final Course? course;
  @override
  State<CourseEditor> createState() => _CourseEditorState();
}

class _CourseEditorState extends State<CourseEditor> {
  late final _name = TextEditingController(text: widget.course?.name ?? '');
  late final _credits = TextEditingController(
    text: '${widget.course?.credits ?? 3}',
  );
  late final _point = TextEditingController(
    text: widget.course?.gradePoint?.toString() ?? '',
  );
  late String _semesterId =
      widget.course?.semesterId ?? widget.semesters.first.id;
  late final _id =
      widget.course?.id ?? 'course-${DateTime.now().microsecondsSinceEpoch}';
  late final List<_SlotDraft> _slots =
      widget.course?.slots.map(_SlotDraft.new).toList() ??
      [_SlotDraft(null, _defaultWeeksText)];
  @override
  void dispose() {
    _name.dispose();
    _credits.dispose();
    _point.dispose();
    for (final s in _slots) {
      s.dispose();
    }
    super.dispose();
  }

  /// 当前选中的学期；用于把周次上界限制在该学期的实际周数内。
  Semester? get _selectedSemester {
    for (final semester in widget.semesters) {
      if (semester.id == _semesterId) return semester;
    }
    return null;
  }

  /// 新建课程时预填的周次文本：跟随所选学期的合法范围，
  /// 避免默认值本身就超出学期而被拒绝。
  String get _defaultWeeksText {
    final maxWeek = _selectedSemester?.lastValidWeek ?? 16;
    return maxWeek >= 1 ? '1-$maxWeek' : '1';
  }

  Future<void> _save() async {
    final credits = double.tryParse(_credits.text.trim());
    final point = _point.text.trim().isEmpty
        ? null
        : double.tryParse(_point.text.trim());
    if (_name.text.trim().isEmpty) throw const FormatException('课程名称不能为空');
    if (credits == null || !credits.isFinite || credits <= 0) {
      throw const FormatException('学分必须是有限正数');
    }
    if (_point.text.trim().isNotEmpty &&
        (point == null ||
            !point.isFinite ||
            point < 0 ||
            point > CampusStore.scoreScaleMax)) {
      throw const FormatException('绩点填写 0–4，未评分请留空');
    }
    // 周次上界跟随所选学期；学期没有可用周次时不允许保存任何时段。
    // 逐个时段构建，报错时指明是第几个时段，便于定位。
    final maxWeek = _selectedSemester?.lastValidWeek;
    final slots = <CourseSlot>[];
    for (var i = 0; i < _slots.length; i++) {
      try {
        slots.add(_slots[i].build(maxWeek: maxWeek));
      } on FormatException catch (error) {
        throw FormatException('时段 ${i + 1}：${error.message}');
      }
    }
    final course = Course(
      id: _id,
      semesterId: _semesterId,
      name: _name.text.trim(),
      credits: credits,
      gradePoint: point,
      slots: slots,
      scoreScaleMax: CampusStore.scoreScaleMax,
    );
    await widget.data.academic.saveCourse(
      course,
      creating: widget.course == null,
    );
  }

  @override
  Widget build(BuildContext context) => RecordEditorDialog(
    title: widget.course == null ? '新建课程' : '编辑课程',
    onSave: _save,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _semesterId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '所属学期'),
          items: widget.semesters
              .map(
                (v) => DropdownMenuItem(
                  value: v.id,
                  child: Text(v.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _semesterId = v);
          },
        ),
        TextField(
          key: const Key('course-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: '课程名称'),
        ),
        TextField(
          key: const Key('course-credits'),
          controller: _credits,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '学分'),
        ),
        TextField(
          key: const Key('course-point'),
          controller: _point,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '绩点（0–4，未评分留空）'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('每周上课时间 · 可添加多个时段；无固定课时可全部移除'),
        ),
        for (var i = 0; i < _slots.length; i++)
          Card(
            key: ObjectKey(_slots[i]),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('时段 ${i + 1}')),
                      IconButton(
                        tooltip: '移除此时段',
                        onPressed: () {
                          final removed = _slots[i];
                          setState(() => _slots.removeAt(i));
                          removed.dispose();
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: _slots[i].weekday,
                    isExpanded: true,
                    items: List.generate(
                      7,
                      (n) => DropdownMenuItem(
                        value: n + 1,
                        child: Text(
                          '周${const ['一', '二', '三', '四', '五', '六', '日'][n]}',
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) setState(() => _slots[i].weekday = v);
                    },
                  ),
                  TextField(
                    key: Key('course-start-$i'),
                    controller: _slots[i].start,
                    decoration: const InputDecoration(labelText: '开始（HH:mm）'),
                  ),
                  TextField(
                    key: Key('course-end-$i'),
                    controller: _slots[i].end,
                    decoration: const InputDecoration(
                      labelText: '结束（HH:mm，可填 24:00）',
                    ),
                  ),
                  TextField(
                    key: Key('course-weeks-$i'),
                    controller: _slots[i].weeks,
                    decoration: InputDecoration(
                      labelText: '周次',
                      hintText: '1,3 / 1-3 / 1-16单',
                      helperText: _selectedSemester == null
                          ? '示例：1,3 单独两周；1-3 连续三周；1-16单 单周；1-16双 双周'
                          : '示例：1,3 / 1-3 / 1-16单；本学期可用 '
                                '${_selectedSemester!.weekRangeLabel}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        TextButton.icon(
          onPressed: () =>
              setState(() => _slots.add(_SlotDraft(null, _defaultWeeksText))),
          icon: const Icon(Icons.add),
          label: const Text('添加上课时段'),
        ),
      ],
    ),
  );
}
