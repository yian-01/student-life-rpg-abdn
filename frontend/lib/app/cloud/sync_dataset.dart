import 'dart:convert';

import '../../features/schedule/repositories/file_task_repository.dart';
import '../data/campus_store.dart';
import '../data/full_backup.dart';

typedef SyncRow = Map<String, dynamic>;

enum SyncChoice { local, other }

class SyncDataset {
  SyncDataset(this.backup)
    : _campus = jsonDecode(backup.campus) as SyncRow,
      _tasks = jsonDecode(backup.tasks) as SyncRow;

  static final empty = SyncDataset(
    FullBackup.validate(
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      jsonEncode(CampusStore.emptyDocument()),
      FileTaskRepository.emptyDocument(),
    ),
  );

  static const tables = [...CampusStore.tables, 'tasks'];
  final FullBackup backup;
  final SyncRow _campus;
  final SyncRow _tasks;

  Iterable<SyncRow> _rows(String table) =>
      ((table == 'tasks' ? _tasks['records'] : _campus[table]) as List)
          .cast<SyncRow>();

  Map<String, SyncRow> _index(String table) => {
    for (final row in _rows(table)) row['id'] as String: row,
  };

  bool sameData(SyncDataset other) =>
      tables.every((table) => _same(_index(table), other._index(table)));

  SyncDataset _withRows(Map<String, List<SyncRow>> rows) => SyncDataset(
    FullBackup.validate(
      DateTime.now(),
      jsonEncode({
        ..._campus,
        for (final table in CampusStore.tables) table: rows[table],
      }),
      jsonEncode({..._tasks, 'records': rows['tasks']}),
    ),
  );

  /// Import is additive. A missing guest record must not delete a record
  /// already present in the account, including built-in finance categories.
  SyncDataset forGuestImport() => _withRows({
    for (final table in tables)
      table: {...empty._index(table), ..._index(table)}.values.toList(),
  });

  static bool _same(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.entries.every(
            (entry) =>
                right.containsKey(entry.key) &&
                _same(entry.value, right[entry.key]),
          );
    }
    if (left is List && right is List) {
      return left.length == right.length &&
          List.generate(
            left.length,
            (i) => i,
          ).every((i) => _same(left[i], right[i]));
    }
    return left == right;
  }
}

class SyncConflict {
  const SyncConflict(this.table, this.id, this.local, this.other);
  final String table;
  final String id;
  final SyncRow? local;
  final SyncRow? other;

  String label(SyncRow? row) {
    if (row == null) return '已删除';
    for (final field in const ['title', 'name', 'note', 'description']) {
      final value = row[field];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return id;
  }

  List<String> get fields => local == null || other == null
      ? const []
      : {
          ...local!.keys,
          ...other!.keys,
        }.where((key) => !SyncDataset._same(local![key], other![key])).toList();
}

class SyncMerge {
  const SyncMerge(
    this.dataset,
    this.conflicts, {
    this.invalidReferences = false,
  });
  final SyncDataset? dataset;
  final List<SyncConflict> conflicts;
  final bool invalidReferences;

  static SyncMerge reconcile(
    SyncDataset base,
    SyncDataset local,
    SyncDataset other, {
    SyncChoice? choice,
  }) {
    final conflicts = <SyncConflict>[];
    final merged = <String, List<SyncRow>>{};
    for (final table in SyncDataset.tables) {
      final before = base._index(table);
      final here = local._index(table);
      final there = other._index(table);
      final rows = <SyncRow>[];
      for (final id in {...here.keys, ...there.keys}) {
        final a = here[id];
        final b = there[id];
        final original = before[id];
        final SyncRow? resolved;
        if (SyncDataset._same(a, b) || SyncDataset._same(b, original)) {
          resolved = a;
        } else if (SyncDataset._same(a, original)) {
          resolved = b;
        } else {
          conflicts.add(SyncConflict(table, id, a, b));
          resolved = choice == SyncChoice.other ? b : a;
        }
        if (resolved != null) rows.add(resolved);
      }
      merged[table] = rows;
    }
    if (choice == null && conflicts.isNotEmpty) {
      return SyncMerge(null, conflicts);
    }
    try {
      return SyncMerge(local._withRows(merged), conflicts);
    } on FormatException {
      // A deletion on one device can invalidate a related record added on the
      // other device. Require a complete-version choice in that case.
      return SyncMerge(null, conflicts, invalidReferences: true);
    }
  }
}
