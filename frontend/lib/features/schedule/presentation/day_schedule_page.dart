import '../../../app/module_body.dart';
import 'package:flutter/material.dart';
import '../../../shared/presentation/undo_removal.dart';
import '../services/copy_schedule_item.dart';

import '../../../shared/models/schedule_item.dart';
import '../../academic/models/assignment.dart';
import '../controllers/day_schedule_controller.dart';
import '../models/task.dart';
import '../services/day_schedule_service.dart';
import 'task_editor_dialog.dart';

/// 单日日程页面：由外部注入 [DayScheduleController]，页面不创建仓库。
class DaySchedulePage extends StatefulWidget {
  const DaySchedulePage({
    super.key,
    required this.controller,
    this.onRecover,
    this.onManageEvents,
    this.onManageAcademic,
    this.onOpenItem,
    this.onOpenAssignment,
    this.onAddAssignment,
    this.onRecoverCampus,
    this.onOpenWeek,
  });

  final Future<void> Function()? onRecover;
  final Future<void> Function(DateTime date)? onManageEvents;
  final Future<void> Function()? onManageAcademic;
  final Future<void> Function(ScheduleItem item)? onOpenItem;
  final Future<void> Function(Assignment assignment)? onOpenAssignment;
  final Future<void> Function(DateTime date)? onAddAssignment;
  final Future<void> Function()? onRecoverCampus;
  final Future<DateTime?> Function(DateTime date)? onOpenWeek;
  final DayScheduleController controller;

  @override
  State<DaySchedulePage> createState() => _DaySchedulePageState();
}

class _DaySchedulePageState extends State<DaySchedulePage>
    with WidgetsBindingObserver {
  bool _adding = false;
  bool _managingEvents = false;
  bool _recovering = false;
  bool _opening = false;
  final Set<String> _savingTasks = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.controller.schedule != null ||
          widget.controller.isLoading) {
        return;
      }
      widget.controller.loadDay();
    });
  }

  @override
  void didUpdateWidget(DaySchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_onControllerChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_adding &&
        !_opening &&
        !_managingEvents) {
      widget.controller.retry();
    }
  }

  Future<void> _open(Future<void> Function() action) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await action();
      if (mounted) await widget.controller.retry();
    } catch (_) {
      _showMessage('详情打开失败，请重试。');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  ValueChanged<bool>? _toggleCallbackFor(ScheduleItem item) {
    if (!widget.controller.canEditTasks ||
        item.sourceType != ScheduleSourceType.task ||
        _savingTasks.contains(item.sourceId)) {
      return null;
    }
    return (value) => _setCompleted(item.sourceId, value);
  }

  Future<void> _setCompleted(String taskId, bool isCompleted) async {
    if (_savingTasks.contains(taskId)) return;
    setState(() => _savingTasks.add(taskId));
    try {
      await widget.controller.setTaskCompleted(taskId, isCompleted);
    } catch (_) {
      _showMessage('更新完成状态失败，请重试。');
    } finally {
      if (mounted) setState(() => _savingTasks.remove(taskId));
    }
  }

  Future<void> _showAddTaskDialog() => _showEditor();

  Future<void> _showEditor([String? id, bool copy = false]) async {
    if (_adding || (id != null && _savingTasks.contains(id))) return;
    setState(() => _adding = true);
    try {
      var task = id == null ? null : await widget.controller.taskById(id);
      if (!mounted) return;
      var date = widget.controller.selectedDate;
      final copyAnchor = copy
          ? task?.scheduledRange?.start ?? task?.dueAt
          : null;
      if (copy && task != null) {
        final target = await chooseCopyDate(context, date);
        if (target == null || !mounted) return;
        date = target;
        task = taskCopyDraft(task, target);
      }
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => TaskEditorDialog(
          task: task,
          selectedDate: date,
          copying: copy,
          copyAnchor: copyAnchor,
          onSave: (value) => id == null || copy
              ? widget.controller.addTask(
                  title: value.title,
                  estimatedMinutes: value.estimatedMinutes,
                  dueAt: value.dueAt,
                  scheduledRange: value.scheduledRange,
                  note: value.note,
                  priority: value.priority,
                  steps: value.steps,
                )
              : widget.controller.updateTask(
                  id,
                  title: value.title,
                  estimatedMinutes: value.estimatedMinutes,
                  dueAt: value.dueAt,
                  scheduledRange: value.scheduledRange,
                  note: value.note,
                  priority: value.priority,
                  steps: value.steps,
                ),
        ),
      );
      if (copy && saved == true && mounted) {
        await widget.controller.loadDay(date);
      }
    } catch (_) {
      _showMessage('任务读取失败，请重试。');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeTask(String id) async {
    if (_savingTasks.contains(id)) return;
    setState(() => _savingTasks.add(id));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除任务？'),
          content: const Text('删除后可在本次会话内短时撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final controller = widget.controller;
      final repository = controller.taskRepository!;
      final task = await controller.taskById(id);
      await controller.removeTask(id);
      if (mounted) {
        offerRemovalUndo(context, task.title, () async {
          await repository.insert(task);
          if (mounted) await widget.controller.loadDay();
        });
      }
    } catch (_) {
      _showMessage('删除失败，任务已保留，请重试。');
    } finally {
      if (mounted) setState(() => _savingTasks.remove(id));
    }
  }

  ValueChanged<String>? _actionsFor(String id) =>
      !widget.controller.canEditTasks || _adding || _savingTasks.contains(id)
      ? null
      : (action) {
          if (action == 'edit') {
            _showEditor(id);
          }
          if (action == 'copy') _showEditor(id, true);
          if (action == 'delete') {
            _removeTask(id);
          }
        };

  Future<void> _manageEvents() async {
    if (_managingEvents) return;
    setState(() => _managingEvents = true);
    try {
      await widget.onManageEvents!(widget.controller.selectedDate);
      if (mounted) await widget.controller.loadDay();
    } catch (_) {
      _showMessage('事件管理打开失败，请重试。');
    } finally {
      if (mounted) setState(() => _managingEvents = false);
    }
  }

  Future<void> _recover([bool campus = false]) async {
    if (_recovering) return;
    setState(() => _recovering = true);
    try {
      await (campus ? widget.onRecoverCampus! : widget.onRecover!)();
      if (mounted) await widget.controller.retry();
    } catch (_) {
      _showMessage('恢复失败，当前列表已保留，请检查备份后重试。');
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  Widget _conflictNotice(DaySchedule day) {
    final pairs = widget.controller.conflicts;
    if (pairs.isEmpty) return const SizedBox.shrink();
    final items = {for (final item in day.items) item.id: item};
    return Card(
      key: const Key('day-schedule-conflicts'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '时间冲突 · ${pairs.length} 对冲突',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('可以保留安排，也可编辑任务调整时间。'),
            for (final pair in pairs)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_sourceLabel(items[pair.firstId]!.sourceType)}：${items[pair.firstId]!.title} / '
                  '${_sourceLabel(items[pair.secondId]!.sourceType)}：${items[pair.secondId]!.title}\n'
                  '${_formatDateTime(pair.overlapRange.start)} — ${_formatDateTime(pair.overlapRange.end)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.controller.schedule;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程手账'),
        actions: [
          IconButton(
            key: const Key('refresh-schedule'),
            tooltip: '刷新日程',
            onPressed: widget.controller.isLoading
                ? null
                : widget.controller.retry,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.onManageAcademic != null)
            IconButton(
              key: const Key('manage-academic'),
              tooltip: '管理课程、作业与考试',
              icon: const Icon(Icons.school),
              onPressed: _opening
                  ? null
                  : () => _open(widget.onManageAcademic!),
            ),
          if (widget.onManageEvents != null)
            IconButton(
              key: const Key('manage-events'),
              tooltip: '管理事件',
              icon: const Icon(Icons.event_note),
              onPressed: _managingEvents ? null : _manageEvents,
            ),

          if (widget.onRecover != null)
            IconButton(
              tooltip: '重新读取 / 从备份恢复',
              onPressed: _recovering ? null : () => _recover(),
              icon: const Icon(Icons.restore),
            ),
        ],
      ),
      body: ModuleBody(
        child: SafeArea(
          child: Column(
            children: [
              if (widget.controller.demoData) const _DemoDataBanner(),
              _DateNavigator(controller: widget.controller),
              if (widget.onOpenWeek != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.view_week_outlined),
                    label: const Text('周课表'),
                    onPressed: () async {
                      final target = await widget.onOpenWeek!(
                        widget.controller.selectedDate,
                      );
                      if (mounted) await widget.controller.loadDay(target);
                    },
                  ),
                ),
              const Divider(height: 1),
              Expanded(child: _buildBody(schedule)),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.controller.canEditTasks
          ? FloatingActionButton.extended(
              key: const Key('day-schedule-add-task'),
              onPressed: _adding ? null : _showAddTaskDialog,
              icon: const Icon(Icons.add),
              label: const Text('添加任务'),
            )
          : null,
    );
  }

  Widget _buildBody(DaySchedule? schedule) {
    if (widget.controller.isLoading && schedule == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('day-schedule-loading')),
      );
    }

    if (widget.controller.errorMessage != null && schedule == null) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                widget.controller.errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.controller.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (schedule == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      key: const Key('schedule-day-list'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        if (widget.controller.isLoading) const LinearProgressIndicator(),
        ..._sourceErrors(schedule),
        if (widget.onRecover != null)
          const ModuleNotice('任务自动保存在本机。可分别设置安排时间与截止时间。'),
        _conflictNotice(schedule),
        const _SectionTitle('当天日程'),
        if (schedule.items.isEmpty)
          _EmptyMessage(
            schedule.errors.keys.any(
                  (source) => source != ScheduleDataSource.assignments,
                )
                ? '部分日程未能读取，请先重试或恢复。'
                : '今日暂无已排程事项',
          )
        else
          ...schedule.items.map(
            (item) => _ScheduledItemTile(
              item: item,
              completed: schedule.isCompletedTask(item),
              crossDay: schedule.isCrossDay(item),
              loadTask:
                  item.sourceType == ScheduleSourceType.task &&
                      widget.controller.taskRepository != null
                  ? () => widget.controller.taskById(item.sourceId)
                  : null,
              onOpen: item.sourceType == ScheduleSourceType.task
                  ? (widget.controller.canEditTasks
                        ? () => _showEditor(item.sourceId)
                        : null)
                  : (widget.onOpenItem == null || _opening
                        ? null
                        : () => _open(() => widget.onOpenItem!(item))),
              onToggleComplete: _toggleCallbackFor(item),
              onAction: item.sourceType == ScheduleSourceType.task
                  ? _actionsFor(item.sourceId)
                  : null,
            ),
          ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const _SectionTitle('当日作业截止'),
            if (widget.onAddAssignment != null &&
                !schedule.errors.containsKey(ScheduleDataSource.assignments))
              TextButton.icon(
                key: const Key('schedule-new-assignment'),
                onPressed: _opening
                    ? null
                    : () => _open(
                        () => widget.onAddAssignment!(
                          widget.controller.selectedDate,
                        ),
                      ),
                icon: const Icon(Icons.add),
                label: const Text('新建作业'),
              ),
          ],
        ),
        if (schedule.assignmentDeadlines.isEmpty)
          _EmptyMessage(
            schedule.errors.containsKey(ScheduleDataSource.assignments)
                ? '作业截止未能读取。'
                : '今日暂无作业截止',
          )
        else
          for (final assignment in schedule.assignmentDeadlines)
            Card(
              child: ListTile(
                key: Key('assignment-deadline-${assignment.id}'),
                leading: const Icon(Icons.assignment_outlined),
                title: Text(assignment.title),
                subtitle: Text('作业截止 · ${_formatDateTime(assignment.dueAt)}'),
                onTap: widget.onOpenAssignment == null || _opening
                    ? null
                    : () => _open(() => widget.onOpenAssignment!(assignment)),
              ),
            ),
        const SizedBox(height: 20),
        const _SectionTitle('未安排任务（全部日期）'),
        if (schedule.unscheduledTasks.isEmpty)
          Column(
            children: [
              _EmptyMessage(
                schedule.errors.containsKey(ScheduleDataSource.tasks)
                    ? '任务未能读取。'
                    : '暂无未安排任务',
              ),
              if (widget.controller.canEditTasks)
                TextButton.icon(
                  onPressed: _adding ? null : _showAddTaskDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('创建第一项任务'),
                ),
            ],
          )
        else
          ...schedule.unscheduledTasks.map(
            (task) => _UnscheduledTaskTile(
              task: task,
              onAction: _actionsFor(task.id),
              onToggleComplete:
                  widget.controller.canEditTasks &&
                      !_savingTasks.contains(task.id)
                  ? (value) => _setCompleted(task.id, value)
                  : null,
            ),
          ),
        if (schedule.completedTasks.isNotEmpty)
          ExpansionTile(
            key: const Key('completed-tasks'),
            title: Text('已完成任务（全部）· ${schedule.completedTasks.length}'),
            children: [
              for (final task in schedule.completedTasks)
                _UnscheduledTaskTile(
                  task: task,
                  onAction: _actionsFor(task.id),
                  onToggleComplete:
                      widget.controller.canEditTasks &&
                          !_savingTasks.contains(task.id)
                      ? (v) => _setCompleted(task.id, v)
                      : null,
                ),
            ],
          ),
      ],
    );
  }

  List<Widget> _sourceErrors(DaySchedule schedule) {
    final tasksFailed = schedule.errors.containsKey(ScheduleDataSource.tasks);
    final campusFailed = schedule.errors.keys.any(
      (source) => source != ScheduleDataSource.tasks,
    );
    Widget notice(String key, String label, VoidCallback? recover) => Card(
      key: Key(key),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label读取失败。健康来源仍可使用；如有旧记录，为上次成功读取的数据。'),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: widget.controller.isLoading
                      ? null
                      : widget.controller.retry,
                  child: const Text('重试'),
                ),
                if (recover != null)
                  TextButton(
                    onPressed: _recovering ? null : recover,
                    child: Text('恢复$label'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    return [
      if (tasksFailed)
        notice(
          'schedule-task-error',
          '任务',
          widget.onRecover == null ? null : () => _recover(),
        ),
      if (campusFailed)
        notice(
          'schedule-campus-error',
          '学业／事件',
          widget.onRecoverCampus == null ? null : () => _recover(true),
        ),
    ];
  }
}

/// 明确标注演示数据边界：仅存内存，退出后不保留。
class _DemoDataBanner extends StatelessWidget {
  const _DemoDataBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('day-schedule-demo-banner'),
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        '演示数据：仅存内存，退出后不保留',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
      ),
    );
  }
}

class _DateNavigator extends StatefulWidget {
  const _DateNavigator({required this.controller});

  final DayScheduleController controller;

  @override
  State<_DateNavigator> createState() => _DateNavigatorState();
}

class _DateNavigatorState extends State<_DateNavigator> {
  bool _choosing = false;

  Future<void> _chooseDate() async {
    if (_choosing) return;
    setState(() => _choosing = true);
    try {
      final date = await showDatePicker(
        context: context,
        initialDate: widget.controller.selectedDate,
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, 31),
      );
      if (date != null && mounted) await widget.controller.loadDay(date);
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final selected = controller.selectedDate;
    final monday = DateTime(
      selected.year,
      selected.month,
      selected.day - selected.weekday + 1,
    );
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '前一天',
                onPressed: controller.goToPreviousDay,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('schedule-select-date'),
                  onPressed: _choosing ? null : _chooseDate,
                  child: Text(
                    _formatDate(selected),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: '后一天',
                onPressed: controller.goToNextDay,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Material(
                            color: selected.weekday == i + 1
                                ? scheme.primary
                                : scheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => controller.loadDay(
                                DateTime(
                                  monday.year,
                                  monday.month,
                                  monday.day + i,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      const [
                                        '一',
                                        '二',
                                        '三',
                                        '四',
                                        '五',
                                        '六',
                                        '日',
                                      ][i],
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: selected.weekday == i + 1
                                            ? scheme.onPrimary
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${DateTime(monday.year, monday.month, monday.day + i).day}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: selected.weekday == i + 1
                                            ? scheme.onPrimary
                                            : scheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              TextButton(
                key: const Key('schedule-today'),
                onPressed: () => controller.loadDay(DateTime.now()),
                child: const Text('今天'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Row(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 28,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduledItemTile extends StatelessWidget {
  const _ScheduledItemTile({
    required this.item,
    required this.completed,
    required this.crossDay,
    this.loadTask,
    this.onToggleComplete,
    this.onAction,
    this.onOpen,
  });

  final ValueChanged<String>? onAction;
  final VoidCallback? onOpen;
  final ScheduleItem item;
  final bool completed;
  final bool crossDay;
  final Future<Task> Function()? loadTask;
  final ValueChanged<bool>? onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final timeRange = _formatRange(item);
    final subtitle =
        '${item.sourceType == ScheduleSourceType.task ? '计划 ' : ''}'
        '$timeRange${crossDay ? ' · 跨日' : ''}';
    final toggle = onToggleComplete;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: Key('schedule-item-${item.id}'),
            onTap: onOpen,
            leading: Icon(switch (item.sourceType) {
              ScheduleSourceType.course => Icons.school_outlined,
              ScheduleSourceType.event => Icons.event_note,
              ScheduleSourceType.task => Icons.task_alt,
              ScheduleSourceType.exam => Icons.quiz_outlined,
            }),
            title: Text(item.title),
            subtitle: Text('${_sourceLabel(item.sourceType)}\n$subtitle'),
            trailing: item.sourceType == ScheduleSourceType.task
                ? _TaskActions(
                    id: item.sourceId,
                    completed: completed,
                    onToggle: toggle,
                    onAction: onAction,
                  )
                : null,
          ),
          if (loadTask != null)
            _ScheduledTaskDetails(
              key: Key('scheduled-task-details-${item.sourceId}'),
              loadTask: loadTask!,
            ),
        ],
      ),
    );
  }
}

class _ScheduledTaskDetails extends StatefulWidget {
  const _ScheduledTaskDetails({super.key, required this.loadTask});

  final Future<Task> Function() loadTask;

  @override
  State<_ScheduledTaskDetails> createState() => _ScheduledTaskDetailsState();
}

class _ScheduledTaskDetailsState extends State<_ScheduledTaskDetails> {
  Future<Task>? _future;

  void _load() {
    if (_future != null) return;
    final future = widget.loadTask();
    setState(() {
      _future = future;
    });
  }

  @override
  void didUpdateWidget(_ScheduledTaskDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadTask != widget.loadTask) {
      _future = widget.loadTask();
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('任务详情'),
    onExpansionChanged: (expanded) {
      if (expanded) _load();
    },
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_future == null)
        const SizedBox.shrink()
      else
        FutureBuilder<Task>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              );
            }
            final task = snapshot.data;
            if (task == null || snapshot.hasError) {
              return Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    const Text('任务详情读取失败，请重试。'),
                    TextButton(
                      onPressed: () => setState(() {
                        _future = widget.loadTask();
                      }),
                      child: const Text('重试详情'),
                    ),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('估时 ${task.estimatedMinutes} 分钟'),
                if (task.scheduledRange != null)
                  Text(
                    '计划 ${_formatDateTime(task.scheduledRange!.start)} → ${_formatDateTime(task.scheduledRange!.end)}',
                  ),
                Text(
                  task.dueAt == null
                      ? '截止：未设置'
                      : '截止 ${_formatDateTime(task.dueAt!)}',
                ),
              ],
            );
          },
        ),
    ],
  );
}

class _UnscheduledTaskTile extends StatelessWidget {
  const _UnscheduledTaskTile({
    required this.task,
    this.onToggleComplete,
    this.onAction,
  });

  final ValueChanged<String>? onAction;

  final Task task;
  final ValueChanged<bool>? onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final due = task.dueAt == null
        ? '无截止时间'
        : '截止 ${_formatDateTime(task.dueAt!)}';
    final toggle = onToggleComplete;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.pending_actions)),
        title: Text(task.title),
        subtitle: Text('${task.estimatedMinutes} 分钟 · $due'),
        trailing: _TaskActions(
          id: task.id,
          completed: task.isCompleted,
          onToggle: toggle,
          onAction: onAction,
        ),
      ),
    );
  }
}

class _TaskActions extends StatelessWidget {
  const _TaskActions({
    required this.id,
    required this.completed,
    this.onToggle,
    this.onAction,
  });
  final String id;
  final bool completed;
  final ValueChanged<bool>? onToggle;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (onToggle != null)
        Checkbox(value: completed, onChanged: (v) => onToggle!(v ?? false))
      else if (completed)
        const Icon(Icons.check, semanticLabel: '已完成'),
      if (onAction != null)
        PopupMenuButton<String>(
          key: Key('task-actions-$id'),
          tooltip: '任务操作',
          onSelected: onAction,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑 / 安排时间')),
            PopupMenuItem(value: 'copy', child: Text('复制任务')),
            PopupMenuItem(value: 'delete', child: Text('删除任务')),
          ],
        ),
    ],
  );
}

String _sourceLabel(ScheduleSourceType sourceType) {
  switch (sourceType) {
    case ScheduleSourceType.course:
      return '课程';
    case ScheduleSourceType.event:
      return '事件';
    case ScheduleSourceType.task:
      return '任务';
    case ScheduleSourceType.exam:
      return '考试';
  }
}

String _formatDate(DateTime date) {
  return '${date.year}-${_two(date.month)}-${_two(date.day)}';
}

String _formatDateTime(DateTime dateTime) {
  return '${_formatDate(dateTime)} ${_formatTime(dateTime)}';
}

String _formatTime(DateTime dateTime) {
  return '${_two(dateTime.hour)}:${_two(dateTime.minute)}';
}

String _formatRange(ScheduleItem item) {
  final start = item.range.start;
  final end = item.range.end;
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return '${_formatTime(start)} - ${_formatTime(end)}';
  }
  if (start.year != end.year) {
    return '${_formatDateTime(start)} → ${_formatDateTime(end)}';
  }
  String short(DateTime value) =>
      '${_two(value.month)}-${_two(value.day)} ${_formatTime(value)}';
  return '${short(start)} → ${short(end)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
