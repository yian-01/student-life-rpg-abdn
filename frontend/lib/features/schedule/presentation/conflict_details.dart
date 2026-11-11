import 'package:flutter/material.dart';
import '../../../shared/models/schedule_item.dart';
import '../services/conflict_detector.dart';

/// Owner #32 injects exam type labels by derived item ID, never by title.
class ConflictDetails extends StatelessWidget {
  const ConflictDetails({
    super.key,
    required this.items,
    this.typeLabels = const {},
  });
  final List<ScheduleItem> items;
  final Map<String, String> typeLabels;
  @override
  Widget build(BuildContext context) {
    final pairs = findConflicts(items);
    final byId = {for (final item in items) item.id: item};
    String label(String id) {
      final item = byId[id]!;
      const sourceLabels = {
        'course': '课程',
        'task': '任务',
        'event': '事件',
        'exam': '考试',
      };
      final source = item.sourceType.name;
      final type = typeLabels[id] ?? sourceLabels[source] ?? source;
      return '$type · ${item.title}（${item.sourceId}）';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pairs.isEmpty ? '暂无时段冲突' : '${pairs.length}对冲突'),
        for (final pair in pairs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label(pair.firstId)),
                Text(label(pair.secondId)),
                Text('${pair.overlapRange.start} — ${pair.overlapRange.end}'),
              ],
            ),
          ),
      ],
    );
  }
}
