import 'package:flutter/material.dart';
import '../../../app/data/campus_data.dart';
import '../../../app/data/campus_store.dart';
import '../models/semester.dart';
import '../services/timetable_import.dart';
import '../services/timetable_import_plan.dart';

/// 从教务系统课表导入课程。
///
/// 流程：粘贴课表文本 → 选择学期 → 预览（新增/更新/无变化/需修正）→
/// 修正（勾选与补填学分）→ 确认导入。
/// 预览阶段取消不会写入任何数据。
class TimetableImportPage extends StatefulWidget {
  const TimetableImportPage({
    super.key,
    required this.data,
    required this.semesters,
    this.initialSemesterId,
  });

  final CampusData data;
  final List<Semester> semesters;
  final String? initialSemesterId;

  @override
  State<TimetableImportPage> createState() => _TimetableImportPageState();
}

class _TimetableImportPageState extends State<TimetableImportPage> {
  final _text = TextEditingController();
  final _creditsEditors = <String, TextEditingController>{};
  late String? _semesterId =
      widget.initialSemesterId ??
      (widget.semesters.isEmpty ? null : widget.semesters.first.id);
  ImportPlan? _plan;
  List<TimetableIssue> _issues = const [];
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _text.dispose();
    for (final editor in _creditsEditors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  Future<void> _parse() async {
    final semesterId = _semesterId;
    if (semesterId == null) {
      setState(() => _error = '请先选择学期；没有学期请先回到上一个页面新建。');
      return;
    }
    if (_text.text.trim().isEmpty) {
      setState(() => _error = '请先粘贴课表文本。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      final parsed = parseTimetableText(_text.text);
      final existing = await widget.data.courses.list();
      final plan = buildImportPlan(
        parsed: parsed,
        existingCourses: existing,
        semesterId: semesterId,
        scoreScaleMax: CampusStore.scoreScaleMax,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _issues = parsed.issues;
        for (final item in plan.items) {
          final credits = item.parsed.credits;
          _creditsEditors[item.parsed.name] = TextEditingController(
            text: credits == null ? '' : '$credits',
          );
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '解析失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, double> _creditsOverrides() {
    final result = <String, double>{};
    for (final entry in _creditsEditors.entries) {
      final value = double.tryParse(entry.value.text.trim());
      if (value != null) result[entry.key] = value;
    }
    return result;
  }

  Future<void> _confirm() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final courses = coursesFromPlan(
        plan,
        scoreScaleMax: CampusStore.scoreScaleMax,
        creditsOverrides: _creditsOverrides(),
      );
      var created = 0;
      var updated = 0;
      for (final course in courses) {
        final existed = plan.items.any(
          (item) => item.existing?.id == course.id && item.existing != null,
        );
        if (existed) {
          await widget.data.courses.update(course);
          updated++;
        } else {
          await widget.data.courses.insert(course);
          created++;
        }
      }
      if (!mounted) return;
      setState(() {
        _done = '已导入：新增 $created 门、更新 $updated 门。';
        _plan = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('从课表导入')),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          '在教务系统的课表页面按 Ctrl+A 全选、Ctrl+C 复制，'
          '然后粘贴到下面。只做本地解析，不会联网、不会上传。',
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('timetable-input'),
          controller: _text,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: '课表文本',
            hintText: '个人课表查询\n*学年\t*学期\n……',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('timetable-semester'),
          initialValue: _semesterId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '导入到哪个学期'),
          items: widget.semesters
              .map(
                (semester) => DropdownMenuItem(
                  value: semester.id,
                  child: Text(semester.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _semesterId = value),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('parse-button'),
          onPressed: _busy ? null : _parse,
          icon: const Icon(Icons.search),
          label: Text(_busy ? '处理中…' : '解析并预览'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_done != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_done!)),
        if (_issues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('解析提示 ${_issues.length} 条：'),
                for (final issue in _issues.take(8))
                  Text('· $issue', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        if (_plan != null) ...[
          const Divider(height: 24),
          Text(
            _plan!.summary,
            key: const Key('import-summary'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final item in _plan!.items)
            _PlanTile(
              item: item,
              credits: _creditsEditors[item.parsed.name],
              onToggle: (value) => setState(() => item.selected = value),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('confirm-import'),
            onPressed: _busy || _plan!.pendingWith(_creditsOverrides()).isEmpty
                ? null
                : _confirm,
            child: Text(
              '确认导入 ${_plan!.pendingWith(_creditsOverrides()).length} 门',
            ),
          ),
        ],
      ],
    ),
  );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.item,
    required this.credits,
    required this.onToggle,
  });

  final ImportPlanItem item;
  final TextEditingController? credits;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final label = switch (item.action) {
      ImportAction.create => '新增',
      ImportAction.updateSlots => '更新时段',
      ImportAction.unchanged => '无变化',
      ImportAction.blocked => '需修正',
    };
    return Card(
      key: Key('plan-item-${item.parsed.name}'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: item.selected,
                  onChanged: item.action == ImportAction.blocked
                      ? null
                      : (value) => onToggle(value ?? false),
                ),
                Expanded(
                  child: Text(
                    item.parsed.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(label: Text(label)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                '${item.parsed.slots.length} 个时段'
                '${item.reason == null ? '' : ' · ${item.reason}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (credits != null && item.action != ImportAction.unchanged)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: TextField(
                  key: Key('plan-credits-${item.parsed.name}'),
                  controller: credits,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '学分（可修正）',
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
