import 'package:flutter/material.dart';
import '../../../shared/presentation/undo_removal.dart';
import '../services/copy_schedule_item.dart';
import '../../../app/campus_recovery.dart';
import '../../../app/data/campus_data.dart';
import '../../../shared/models/time_range.dart';
import '../../../shared/presentation/civil_datetime_field.dart';
import '../../../shared/presentation/record_editor_dialog.dart';
import '../models/event.dart';

class EventManagementPage extends StatefulWidget {
  const EventManagementPage({super.key, required this.data, this.initialDate});
  final CampusData data;
  final DateTime? initialDate;
  @override
  State<EventManagementPage> createState() => _EventManagementPageState();
}

class _EventManagementPageState extends State<EventManagementPage> {
  List<Event> _events = [];
  bool _busy = false;
  bool _editing = false;
  bool _confirming = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.data.eventController.load();
      final events = widget.data.eventController.events;
      if (mounted) setState(() => _events = events);
    } catch (_) {
      if (mounted) setState(() => _error = '事件读取失败，请重试或恢复备份。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Event? event, bool copying = false]) async {
    if (_editing || _busy || _confirming) return;
    setState(() => _editing = true);
    try {
      var draft = event;
      if (copying && event != null) {
        final date = await chooseCopyDate(
          context,
          widget.initialDate ?? DateTime.now(),
        );
        if (date == null || !mounted) return;
        draft = event.copyWith(range: copyRangeToDate(event.range, date));
      }
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EventEditor(
          data: widget.data,
          event: draft,
          copying: copying,
          initialDate: widget.initialDate,
        ),
      );
      if (saved == true && mounted) await _load();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _remove(Event event) async {
    if (_busy || _editing || _confirming) return;
    setState(() => _confirming = true);
    try {
      if (!await confirmRemoval(context, event.title, undoable: true) ||
          !mounted)
        return;
      setState(() => _busy = true);
      final repository = widget.data.events;
      if (!await repository.remove(event.id)) throw StateError('Missing event');
      if (!mounted) return;
      offerRemovalUndo(context, event.title, () async {
        await repository.insert(event);
        if (mounted) await _load();
      });
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '删除失败，请重试。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('事件安排'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _busy || _confirming || _editing ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: '重新读取 / 从备份恢复',
          onPressed: _busy || _confirming || _editing
              ? null
              : () async {
                  if (await recoverCampusData(context, widget.data) &&
                      mounted) {
                    await _load();
                  }
                },
          icon: const Icon(Icons.restore),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_events.isEmpty && !_busy) const Text('暂无事件。新增后会出现在对应日期的日程中。'),
        for (final event in _events)
          Card(
            child: ListTile(
              title: Text(event.title),
              subtitle: Text(
                '${_format(event.range.start)} — ${_format(event.range.end)}${event.description == null ? '' : '\n${event.description}'}',
              ),
              trailing: PopupMenuButton<String>(
                key: Key('event-actions-${event.id}'),
                enabled: !_busy && !_editing && !_confirming,
                onSelected: (v) {
                  if (v == 'edit') {
                    _edit(event);
                  } else if (v == 'copy') {
                    _edit(event, true);
                  } else {
                    _remove(event);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'copy', child: Text('复制事件')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ),
          ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('new-event'),
      onPressed: _busy || _editing || _confirming ? null : () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('新增事件'),
    ),
  );
}

class EventEditor extends StatefulWidget {
  const EventEditor({
    super.key,
    required this.data,
    this.event,
    this.copying = false,
    this.initialDate,
  });
  final CampusData data;
  final Event? event;
  final bool copying;
  final DateTime? initialDate;
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  late final _title = TextEditingController(text: widget.event?.title ?? '');
  late final _description = TextEditingController(
    text: widget.event?.description ?? '',
  );
  late final _anchor = widget.initialDate ?? DateTime.now();
  late DateTime _start =
      widget.event?.range.start ??
      DateTime(_anchor.year, _anchor.month, _anchor.day, 9);
  late DateTime _end =
      widget.event?.range.end ??
      DateTime(
        _start.year,
        _start.month,
        _start.day,
        _start.hour + 1,
        _start.minute,
      );
  late final _id =
      (widget.copying ? null : widget.event?.id) ??
      'event-${DateTime.now().microsecondsSinceEpoch}';
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) throw const FormatException('请输入事件标题');
    if (!_start.isBefore(_end)) throw const FormatException('结束时间必须晚于开始时间');
    final event = Event(
      id: _id,
      title: _title.text.trim(),
      range: TimeRange(start: _start, end: _end),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
    );
    await widget.data.eventController.save(
      event,
      creating: widget.copying || widget.event == null,
    );
  }

  @override
  Widget build(BuildContext context) => RecordEditorDialog(
    title: widget.copying
        ? '复制事件'
        : widget.event == null
        ? '新增事件'
        : '编辑事件',
    onSave: _save,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('event-title'),
          controller: _title,
          decoration: const InputDecoration(labelText: '事件标题'),
        ),
        TextField(
          key: const Key('event-description'),
          controller: _description,
          decoration: const InputDecoration(labelText: '备注（可选）'),
        ),
        const SizedBox(height: 12),
        CivilDateTimeField(
          label: '开始',
          value: _start,
          enabled: true,
          onChanged: (v) => setState(() => _start = v),
        ),
        CivilDateTimeField(
          label: '结束',
          value: _end,
          enabled: true,
          onChanged: (v) => setState(() => _end = v),
        ),
      ],
    ),
  );
}

String _format(DateTime v) =>
    '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')} ${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
