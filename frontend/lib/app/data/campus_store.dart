import 'dart:convert';
import 'dart:io';

import '../../features/academic/models/course.dart';
import '../../features/academic/models/semester.dart';
import '../../features/finance/models/finance_category.dart';
import '../../features/finance/models/finance_record.dart';
import '../../features/finance/models/finance_type.dart';
import '../../features/schedule/models/event.dart';
import '../../shared/repositories/entity_repository.dart';
import '../../shared/storage/json_document_store.dart';

/// One serialized transaction boundary for related academic/event/finance data.
/// A failed write never publishes its candidate state. Task schema stays separate.
class CampusStore {
  CampusStore(this.store, this.path);
  final JsonDocumentStore store;
  final String path;
  Map<String, dynamic>? _state;
  Future<void>? _tail;
  static const scoreScaleMax = 4.0;
  static const tables = [
    'semesters',
    'courses',
    'events',
    'categories',
    'records',
  ];

  Future<T> _queue<T>(Future<T> Function() action) {
    // Start in the caller zone rather than scheduling work at construction.
    final result = _tail?.then((_) => action()) ?? Future<T>.sync(action);
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Map<String, dynamic> _fresh() => {
    'schemaVersion': 1,
    'entityType': 'CampusData',
    'scoreScaleMax': scoreScaleMax,
    for (final table in tables) table: <dynamic>[],
    'categories': [
      FinanceCategory(
        id: 'food',
        name: '餐饮',
        type: FinanceType.expense,
      ).toJson(),
      FinanceCategory(
        id: 'transport',
        name: '交通',
        type: FinanceType.expense,
      ).toJson(),
      FinanceCategory(
        id: 'other-expense',
        name: '其他支出',
        type: FinanceType.expense,
      ).toJson(),
      FinanceCategory(
        id: 'allowance',
        name: '生活费',
        type: FinanceType.income,
      ).toJson(),
      FinanceCategory(
        id: 'other-income',
        name: '其他收入',
        type: FinanceType.income,
      ).toJson(),
    ],
  };

  Map<String, dynamic> _decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value.length != 8 ||
        value['schemaVersion'] != 1 ||
        value['entityType'] != 'CampusData' ||
        value['scoreScaleMax'] != scoreScaleMax ||
        !value.keys.toSet().containsAll([
          'schemaVersion',
          'entityType',
          'scoreScaleMax',
          ...tables,
        ])) {
      throw const FormatException('Unsupported CampusData document');
    }
    for (final table in tables) {
      final rows = value[table];
      if (rows is! List) throw FormatException('Invalid $table');
      final ids = <String>{};
      for (final row in rows) {
        if (row is! Map<String, dynamic>) {
          throw FormatException('Invalid $table row');
        }
        switch (table) {
          case 'semesters':
            Semester.fromJson(row);
          case 'courses':
            Course.fromJson(row, scoreScaleMax: scoreScaleMax);
          case 'events':
            Event.fromJson(row);
          case 'categories':
            FinanceCategory.fromJson(row);
          case 'records':
            FinanceRecord.fromJson(row);
        }
        if (!ids.add(row['id'] as String)) {
          throw FormatException('Duplicate $table ID');
        }
      }
    }
    final semesterIds = (value['semesters'] as List)
        .map((v) => v['id'])
        .toSet();
    for (final row in value['courses'] as List) {
      if (!semesterIds.contains(row['semesterId'])) {
        throw const FormatException('Missing semester reference');
      }
    }
    final categories = {
      for (final row in value['categories'] as List) row['id']: row['type'],
    };
    for (final row in value['records'] as List) {
      if (!categories.containsKey(row['categoryId']) ||
          categories[row['categoryId']] != row['type']) {
        throw const FormatException('Invalid category reference/type');
      }
    }
    return value;
  }

  Future<Map<String, dynamic>> _load() async {
    if (_state != null) return _state!;
    final raw = await store.readDocument(path);
    if (raw == null) {
      if (await store.readDocument('$path.bak') != null) {
        throw const FormatException(
          'Main file missing; explicit recovery required',
        );
      }
      return _state = _fresh();
    }
    final loaded = _decode(raw);
    _hasWritten = true;
    return _state = loaded;
  }

  Future<void> initialize() => _queue(() async {
    await _load();
  });

  Future<Map<String, dynamic>> snapshot() => _queue(
    () async => jsonDecode(jsonEncode(await _load())) as Map<String, dynamic>,
  );

  Future<List<Map<String, dynamic>>> rows(String table) => _queue(() async {
    final state = await _load();
    // Deep copies keep callers from mutating committed state.
    return (jsonDecode(jsonEncode(state[table])) as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  });

  Future<bool> mutate(
    String table,
    String id,
    Map<String, dynamic>? row,
    String operation,
  ) => _queue(() async {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    final state = await _load();
    final next = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    final records = next[table] as List;
    final index = records.indexWhere((v) => v['id'] == id);
    if (operation == 'insert' && index >= 0) throw StateError('Duplicate ID');
    if (operation == 'update' && index < 0) throw StateError('Unknown ID');
    if (operation == 'remove' && index < 0) return false;
    if (operation == 'remove') {
      records.removeAt(index);
    } else if (operation == 'insert') {
      records.add(row);
    } else {
      records[index] = row;
    }
    final content = jsonEncode(next);
    try {
      _decode(content);
    } on FormatException catch (e) {
      throw StateError('Invalid reference or entity: ${e.message}');
    }
    // Detect corruption, external replacement or loss before overwriting a file
    // already read by this store. Never refresh stale state by silently dropping it.
    final disk = await store.readDocument(path);
    if (disk != null) {
      final decoded = _decode(disk);
      if (jsonEncode(decoded) != jsonEncode(state)) {
        throw StateError('Storage changed; reload first');
      }
    } else if (_hasWritten || await store.readDocument('$path.bak') != null) {
      throw StateError('Storage missing; explicit recovery required');
    }
    await store.writeDocument(path, content);
    _state = next;
    _hasWritten = true;
    return true;
  });
  bool _hasWritten = false;

  /// User-confirmed disk reload/recovery. Preserve damaged original and valid .bak.
  Future<void> recoverFromBackup() => _queue(() async {
    final raw = await store.readDocument(path);
    if (raw != null) {
      try {
        final valid = _decode(raw);
        _state = valid;
        _hasWritten = true;
        return;
      } on FormatException {
        /* Validate backup before touching the original. */
      }
    }
    final backup = await store.readDocument('$path.bak');
    if (backup == null) throw const FormatException('No valid backup');
    final valid = _decode(backup);
    final main = File(path);
    if (await main.exists()) {
      var archive = '$path.corrupt';
      var sequence = 0;
      while (await FileSystemEntity.type(archive) !=
          FileSystemEntityType.notFound) {
        archive = '$path.corrupt.${++sequence}';
      }
      await main.rename(archive);
    }
    await store.writeDocument(path, backup);
    _state = valid;
    _hasWritten = true;
  });
}

class CampusRepository<T> implements EntityRepository<T> {
  CampusRepository(this.store, this.table, this.decode, this.encode);
  final CampusStore store;
  final String table;
  final T Function(Map<String, dynamic>) decode;
  final Map<String, dynamic> Function(T) encode;
  @override
  Future<List<T>> list() async =>
      List.unmodifiable((await store.rows(table)).map(decode));
  @override
  Future<T?> getById(String id) async {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    for (final row in await store.rows(table)) {
      if (row['id'] == id) return decode(row);
    }
    return null;
  }

  @override
  Future<void> insert(T entity) async {
    final row = encode(entity);
    await store.mutate(table, row['id'] as String, row, 'insert');
  }

  @override
  Future<void> update(T entity) async {
    final row = encode(entity);
    await store.mutate(table, row['id'] as String, row, 'update');
  }

  @override
  Future<bool> remove(String id) => store.mutate(table, id, null, 'remove');
}
