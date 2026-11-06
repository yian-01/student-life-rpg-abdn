import 'dart:convert';
import 'dart:io';

import '../../features/academic/models/assignment.dart';
import '../../features/academic/models/course.dart';
import '../../features/academic/models/exam.dart';
import '../../features/academic/models/semester.dart';
import '../../features/finance/models/budget.dart';
import '../../features/finance/models/finance_category.dart';
import '../../features/finance/models/finance_record.dart';
import '../../features/finance/models/finance_type.dart';
import '../../features/schedule/models/event.dart';
import '../../shared/repositories/entity_repository.dart';
import '../../shared/storage/json_document_store.dart';

/// 一批待写入的行：[table] 取值见 [CampusStore.tables]，每行必须含稳定 `id`。
/// 交给 [CampusStore.applyBatch] 时整批要么全部生效，要么全部不写。
class CampusBatch {
  const CampusBatch({required this.table, required this.rows});

  final String table;
  final List<Map<String, dynamic>> rows;
}

/// One serialized transaction boundary for related academic/event/finance data.
/// A failed write never publishes its candidate state. Task schema stays separate.
class CampusStore {
  CampusStore(this.store, this.path);
  final JsonDocumentStore store;
  final String path;
  Map<String, dynamic>? _state;
  Future<void>? _tail;
  static const scoreScaleMax = 4.0;

  /// 持久化契约 v2：新增 assignments / exams / budgets 三张表。
  static const schemaVersion = 2;
  static const tables = [
    'semesters',
    'courses',
    'assignments',
    'exams',
    'events',
    'categories',
    'records',
    'budgets',
  ];
  static const _v1Tables = [
    'semesters',
    'courses',
    'events',
    'categories',
    'records',
  ];
  static const _baseKeys = {'schemaVersion', 'entityType', 'scoreScaleMax'};

  Future<T> _queue<T>(Future<T> Function() action) {
    // Start in the caller zone rather than scheduling work at construction.
    final result = _tail?.then((_) => action()) ?? Future<T>.sync(action);
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Map<String, dynamic> _fresh() => {
    'schemaVersion': schemaVersion,
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

  /// 解码并校验 CampusData 文档。
  ///
  /// schemaVersion 1 的旧文档自动补齐 v2 新增空表（assignments/exams/budgets），
  /// 原记录保持不变，返回规范 v2 结构并标记 `migrated`；schemaVersion > 2
  /// 或顶层键不匹配的未知未来文档一律拒绝。
  ({Map<String, dynamic> doc, bool migrated}) _decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value['entityType'] != 'CampusData' ||
        value['scoreScaleMax'] != scoreScaleMax) {
      throw const FormatException('Unsupported CampusData document');
    }
    var migrated = false;
    final keys = value.keys.toSet();
    final isV1 =
        value['schemaVersion'] == 1 &&
        keys.length == _v1Tables.length + _baseKeys.length &&
        keys.containsAll({..._baseKeys, ..._v1Tables});
    final isV2 =
        value['schemaVersion'] == schemaVersion &&
        keys.length == tables.length + _baseKeys.length &&
        keys.containsAll({..._baseKeys, ...tables});
    if (isV1) {
      value['schemaVersion'] = schemaVersion;
      value['assignments'] = <dynamic>[];
      value['exams'] = <dynamic>[];
      value['budgets'] = <dynamic>[];
      migrated = true;
    } else if (!isV2) {
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
        final Object? rowId = row['id'];
        switch (table) {
          case 'semesters':
            Semester.fromJson(row);
          case 'courses':
            Course.fromJson(row, scoreScaleMax: scoreScaleMax);
          case 'assignments':
            Assignment.fromJson(row);
          case 'exams':
            Exam.fromJson(row);
          case 'events':
            Event.fromJson(row);
          case 'categories':
            FinanceCategory.fromJson(row);
          case 'records':
            FinanceRecord.fromJson(row);
          case 'budgets':
            // 预算行沿用 finance 模块模型，额外带派生 `id`（= 唯一键）。
            // id 必须等于模型推导出的键，否则按 id 查找与按键写入会不一致。
            final budget = Budget.fromJson(
              Map<String, dynamic>.from(row)..remove('id'),
            );
            if (rowId != budget.key) {
              throw const FormatException(
                'Budget row id must equal its category/month key',
              );
            }
        }
        if (rowId is! String) throw FormatException('Missing $table ID');
        if (!ids.add(rowId)) {
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
    final courseIds = (value['courses'] as List).map((v) => v['id']).toSet();
    for (final table in const ['assignments', 'exams']) {
      for (final row in value[table] as List) {
        if (!courseIds.contains(row['courseId'])) {
          throw FormatException('Missing course reference in $table');
        }
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
    final budgetKeys = <String>{};
    for (final row in value['budgets'] as List) {
      final budget = Budget.fromJson(
        Map<String, dynamic>.from(row as Map<String, dynamic>)..remove('id'),
      );
      // 预算只能建在支出分类上；(categoryId, month) 组合唯一。
      if (categories[budget.categoryId] != 'expense') {
        throw const FormatException(
          'Budget must reference an expense category',
        );
      }
      if (!budgetKeys.add(budget.key)) {
        throw const FormatException('Duplicate budget for category/month');
      }
    }
    return (doc: value, migrated: migrated);
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
    final decoded = _decode(raw);
    if (decoded.migrated) {
      // v1 → v2：先写回升级后的文档（旧版自动留存为 .bak），再提交内存。
      await store.writeDocument(path, jsonEncode(decoded.doc));
    }
    _hasWritten = true;
    return _state = decoded.doc;
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
    } else if (operation == 'put') {
      // 同一唯一键视为同一行：存在则替换，不存在则追加。
      if (index >= 0) {
        records[index] = row;
      } else {
        records.add(row);
      }
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
      final decoded = _decode(disk).doc;
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

  /// 原子批量写入：同一事务内按行 `id` upsert 多张表的记录。
  ///
  /// - 任一行缺失/空白 `id`、批内重复 `id` → [ArgumentError] / [StateError]
  /// - 任一行内容或引用非法 → [StateError]，整批不写盘、内存不变
  /// - 磁盘已被外部改动或丢失 → [StateError]，不覆盖
  /// - 返回本次新增与更新的条数
  Future<({int inserted, int updated})> applyBatch(List<CampusBatch> batches) =>
      _queue(() async {
        final state = await _load();
        final next = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
        var inserted = 0;
        var updated = 0;
        for (final batch in batches) {
          final records = next[batch.table];
          if (records is! List) {
            throw ArgumentError.value(batch.table, 'table', 'Unknown table');
          }
          final batchIds = <String>{};
          for (final row in batch.rows) {
            final id = row['id'];
            if (id is! String || id.trim().isEmpty) {
              throw ArgumentError.value(id, 'id', 'must not be blank');
            }
            if (!batchIds.add(id)) {
              throw StateError('Duplicate ID in batch: $id');
            }
            final index = records.indexWhere((v) => v['id'] == id);
            if (index >= 0) {
              records[index] = row;
              updated++;
            } else {
              records.add(row);
              inserted++;
            }
          }
        }
        final content = jsonEncode(next);
        try {
          _decode(content);
        } on FormatException catch (e) {
          throw StateError('Invalid reference or entity: ${e.message}');
        }
        final disk = await store.readDocument(path);
        if (disk != null) {
          final decoded = _decode(disk).doc;
          if (jsonEncode(decoded) != jsonEncode(state)) {
            throw StateError('Storage changed; reload first');
          }
        } else if (_hasWritten ||
            await store.readDocument('$path.bak') != null) {
          throw StateError('Storage missing; explicit recovery required');
        }
        await store.writeDocument(path, content);
        _state = next;
        _hasWritten = true;
        return (inserted: inserted, updated: updated);
      });

  /// User-confirmed disk reload/recovery. Preserve damaged original and valid .bak.
  Future<void> recoverFromBackup() => _queue(() async {
    final raw = await store.readDocument(path);
    if (raw != null) {
      try {
        final valid = _decode(raw).doc;
        _state = valid;
        _hasWritten = true;
        return;
      } on FormatException {
        /* Validate backup before touching the original. */
      }
    }
    final backup = await store.readDocument('$path.bak');
    if (backup == null) throw const FormatException('No valid backup');
    final valid = _decode(backup).doc;
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
