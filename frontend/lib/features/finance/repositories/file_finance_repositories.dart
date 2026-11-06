// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import '../../../shared/repositories/entity_repository.dart';
import '../../../shared/storage/json_document_store.dart';
import '../models/budget.dart';
import '../models/finance_category.dart';
import '../models/finance_record.dart';
import '../models/finance_type.dart';
import '../models/json_map.dart';
import '../models/local_date_time_json.dart';
import 'budget_repository.dart';
import 'in_memory_finance_repositories.dart';

void _requireId(String id) {
  if (id.trim().isEmpty) {
    throw ArgumentError.value(id, 'id', 'Must not be blank.');
  }
}

/// 单个实体类型的顶层 JSON 文档：`{schemaVersion:1, entityType, records}`。
/// 读取失败时不静默覆盖原件；由调用方决定恢复策略。
class _EntityDocument {
  _EntityDocument({
    required this.store,
    required this.path,
    required this.entityType,
  });

  final JsonDocumentStore store;
  final String path;
  final String entityType;

  static const int schemaVersion = 1;

  Future<List<Map<String, dynamic>>> readAll() async {
    final raw = await store.readDocument(path);
    if (raw == null) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Finance document is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Finance document must be an object.');
    }
    requireExactJsonKeys(
      decoded,
      requiredKeys: const {'schemaVersion', 'entityType', 'records'},
    );
    if (decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported schemaVersion.');
    }
    if (decoded['entityType'] != entityType) {
      throw FormatException('Expected entityType $entityType.');
    }
    final records = decoded['records'];
    if (records is! List) {
      throw const FormatException('records must be a list.');
    }
    return records
        .map((entry) {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Each record must be an object.');
          }
          return entry;
        })
        .toList(growable: false);
  }

  Future<void> writeAll(List<Map<String, dynamic>> records) {
    final content = jsonEncode({
      'schemaVersion': schemaVersion,
      'entityType': entityType,
      'records': records,
    });
    return store.writeDocument(path, content);
  }
}

/// 串行化同一仓库的操作，避免并发写入互相覆盖。
mixin _Serialized {
  Future<void> _queue = Future<void>.value();

  Future<T> serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}

/// 文件持久化的分类仓库。写入成功后才提交内存状态，失败保留旧状态。
class FileFinanceCategoryRepository
    with _Serialized
    implements EntityRepository<FinanceCategory> {
  FileFinanceCategoryRepository({
    required JsonDocumentStore store,
    required String path,
    required Future<Set<String>> Function() recordCategoryIds,
    required Future<Set<String>> Function() budgetCategoryIds,
  }) : _doc = _EntityDocument(
         store: store,
         path: path,
         entityType: 'FinanceCategory',
       ),
       _recordCategoryIds = recordCategoryIds,
       _budgetCategoryIds = budgetCategoryIds;

  final _EntityDocument _doc;
  final Future<Set<String>> Function() _recordCategoryIds;
  final Future<Set<String>> Function() _budgetCategoryIds;
  final Map<String, FinanceCategory> _items = {};
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      final rows = await _doc.readAll();
      for (final row in rows) {
        final category = FinanceCategory.fromJson(row);
        _items[category.id] = category;
      }
      _loaded = true;
    } finally {
      _loading = null;
    }
  }

  Future<void> _persist(Map<String, FinanceCategory> snapshot) async {
    final rows = snapshot.values.map((c) => c.toJson()).toList(growable: false);
    await _doc.writeAll(rows);
    _items
      ..clear()
      ..addAll(snapshot);
  }

  @override
  Future<List<FinanceCategory>> list() => serialize(() async {
    await _ensureLoaded();
    return List<FinanceCategory>.unmodifiable(
      _items.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
    );
  });

  @override
  Future<FinanceCategory?> getById(String id) => serialize(() async {
    _requireId(id);
    await _ensureLoaded();
    return _items[id];
  });

  @override
  Future<void> insert(FinanceCategory entity) => serialize(() async {
    await _ensureLoaded();
    if (_items.containsKey(entity.id)) {
      throw StateError('Duplicate FinanceCategory id: ${entity.id}');
    }
    _assertNoDuplicateName(entity);
    final next = Map<String, FinanceCategory>.from(_items)..[entity.id] = entity;
    await _persist(next);
  });

  @override
  Future<void> update(FinanceCategory entity) => serialize(() async {
    await _ensureLoaded();
    final existing = _items[entity.id];
    if (existing == null) {
      throw StateError('Unknown FinanceCategory id: ${entity.id}');
    }
    _assertNoDuplicateName(entity);
    if (existing.type != entity.type) {
      if ((await _recordCategoryIds()).contains(entity.id)) {
        throw StateError('该分类被收支记录引用，无法修改类型。');
      }
      if ((await _budgetCategoryIds()).contains(entity.id)) {
        throw StateError('该分类被预算引用，无法修改类型。');
      }
    }
    final next = Map<String, FinanceCategory>.from(_items)
      ..[entity.id] = entity;
    await _persist(next);
  });

  @override
  Future<bool> remove(String id) => serialize(() async {
    _requireId(id);
    await _ensureLoaded();
    if (!_items.containsKey(id)) return false;
    if ((await _recordCategoryIds()).contains(id)) {
      throw StateError('该分类被收支记录引用，无法删除。');
    }
    if ((await _budgetCategoryIds()).contains(id)) {
      throw StateError('该分类被预算引用，无法删除。');
    }
    final next = Map<String, FinanceCategory>.from(_items)..remove(id);
    await _persist(next);
    return true;
  });

  void _assertNoDuplicateName(FinanceCategory entity) {
    final duplicate = _items.values.any(
      (other) =>
          other.type == entity.type &&
          other.id != entity.id &&
          other.name.trim().toLowerCase() ==
              entity.name.trim().toLowerCase(),
    );
    if (duplicate) {
      throw StateError('同类型下已存在同名分类。');
    }
  }
}

/// 文件持久化的记录仓库。
class FileFinanceRecordRepository
    with _Serialized
    implements FinanceRecordRepository {
  FileFinanceRecordRepository({
    required JsonDocumentStore store,
    required String path,
    required EntityRepository<FinanceCategory> categories,
  }) : _doc = _EntityDocument(
         store: store,
         path: path,
         entityType: 'FinanceRecord',
       ),
       _categories = categories;

  final _EntityDocument _doc;
  final EntityRepository<FinanceCategory> _categories;
  final Map<String, FinanceRecord> _items = {};
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      final rows = await _doc.readAll();
      for (final row in rows) {
        final record = FinanceRecord.fromJson(row);
        _items[record.id] = record;
      }
      _loaded = true;
    } finally {
      _loading = null;
    }
  }

  Future<void> _persist(Map<String, FinanceRecord> snapshot) async {
    final rows = snapshot.values.map((r) => r.toJson()).toList(growable: false);
    await _doc.writeAll(rows);
    _items
      ..clear()
      ..addAll(snapshot);
  }

  /// 供分类仓库查询引用（不占用本仓库写队列，避免跨仓库死锁）。
  Future<Set<String>> referencedCategoryIds() async {
    await _ensureLoaded();
    return _items.values.map((record) => record.categoryId).toSet();
  }

  @override
  Future<List<FinanceRecord>> list() => serialize(() async {
    await _ensureLoaded();
    return List<FinanceRecord>.unmodifiable(_sorted(_items.values));
  });

  @override
  Future<FinanceRecord?> getById(String id) => serialize(() async {
    _requireId(id);
    await _ensureLoaded();
    return _items[id];
  });

  @override
  Future<void> insert(FinanceRecord entity) => serialize(() async {
    await _ensureLoaded();
    if (_items.containsKey(entity.id)) {
      throw StateError('Duplicate FinanceRecord id: ${entity.id}');
    }
    await _assertCategoryMatches(entity);
    if (_items.containsKey(entity.id)) {
      throw StateError('Duplicate FinanceRecord id: ${entity.id}');
    }
    final next = Map<String, FinanceRecord>.from(_items)
      ..[entity.id] = entity;
    await _persist(next);
  });

  @override
  Future<void> update(FinanceRecord entity) => serialize(() async {
    await _ensureLoaded();
    if (!_items.containsKey(entity.id)) {
      throw StateError('Unknown FinanceRecord id: ${entity.id}');
    }
    await _assertCategoryMatches(entity);
    if (!_items.containsKey(entity.id)) {
      throw StateError('Unknown FinanceRecord id: ${entity.id}');
    }
    final next = Map<String, FinanceRecord>.from(_items)
      ..[entity.id] = entity;
    await _persist(next);
  });

  @override
  Future<bool> remove(String id) => serialize(() async {
    _requireId(id);
    await _ensureLoaded();
    if (!_items.containsKey(id)) return false;
    final next = Map<String, FinanceRecord>.from(_items)..remove(id);
    await _persist(next);
    return true;
  });

  @override
  Future<List<FinanceRecord>> listForMonth(int year, int month) =>
      serialize(() async {
        await _ensureLoaded();
        final start = monthStart(year, month);
        final end = DateTime(year, month + 1);
        final filtered = _items.values.where((record) {
          requireLocalDateTime(record.occurredAt, 'occurredAt');
          return !record.occurredAt.isBefore(start) &&
              record.occurredAt.isBefore(end);
        });
        return List<FinanceRecord>.unmodifiable(_sorted(filtered));
      });

  Future<void> _assertCategoryMatches(FinanceRecord entity) async {
    final category = await _categories.getById(entity.categoryId);
    if (category == null) {
      throw StateError('Unknown finance category: ${entity.categoryId}');
    }
    if (category.type != entity.type) {
      throw StateError('Record type must match category type.');
    }
  }

  List<FinanceRecord> _sorted(Iterable<FinanceRecord> records) {
    return records.toList()..sort((a, b) {
      final byTime = a.occurredAt.compareTo(b.occurredAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
  }
}

/// 文件持久化的预算仓库，键为 `categoryId@yyyy-MM`，保证同一支出类别+年月唯一。
class FileFinanceBudgetRepository with _Serialized implements BudgetRepository {
  FileFinanceBudgetRepository({
    required JsonDocumentStore store,
    required String path,
    required EntityRepository<FinanceCategory> categories,
  }) : _doc = _EntityDocument(
         store: store,
         path: path,
         entityType: 'Budget',
       ),
       _categories = categories;

  final _EntityDocument _doc;
  final EntityRepository<FinanceCategory> _categories;
  final Map<String, Budget> _items = {};
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      final rows = await _doc.readAll();
      for (final row in rows) {
        final budget = Budget.fromJson(row);
        _items[budget.key] = budget;
      }
      _loaded = true;
    } finally {
      _loading = null;
    }
  }

  Future<void> _persist(Map<String, Budget> snapshot) async {
    final rows = snapshot.values.map((b) => b.toJson()).toList(growable: false);
    await _doc.writeAll(rows);
    _items
      ..clear()
      ..addAll(snapshot);
  }

  @override
  Future<List<Budget>> list() => serialize(() async {
    await _ensureLoaded();
    return List<Budget>.unmodifiable(
      _items.values.toList()
        ..sort((a, b) {
          final byMonth = a.month.compareTo(b.month);
          return byMonth != 0 ? byMonth : a.categoryId.compareTo(b.categoryId);
        }),
    );
  });

  @override
  Future<Budget?> getForCategoryMonth(String categoryId, DateTime month) =>
      serialize(() async {
        _requireId(categoryId);
        await _ensureLoaded();
        return _items[budgetKey(categoryId, month)];
      });

  @override
  Future<void> put(Budget budget) => serialize(() async {
    await _ensureLoaded();
    final category = await _categories.getById(budget.categoryId);
    if (category == null) {
      throw StateError('Unknown finance category: ${budget.categoryId}');
    }
    if (category.type != FinanceType.expense) {
      throw StateError('Budgets require an expense category.');
    }
    // 同一键 upsert：唯一性由 Map 保证。
    final next = Map<String, Budget>.from(_items)..[budget.key] = budget;
    await _persist(next);
  });

  @override
  Future<bool> removeForCategoryMonth(String categoryId, DateTime month) =>
      serialize(() async {
        _requireId(categoryId);
        await _ensureLoaded();
        final key = budgetKey(categoryId, month);
        if (!_items.containsKey(key)) return false;
        final next = Map<String, Budget>.from(_items)..remove(key);
        await _persist(next);
        return true;
      });

  @override
  Set<String> referencedCategoryIds() =>
      _items.keys.map((key) => key.split('@').first).toSet();

  /// 供分类仓库查询引用（不占用本仓库写队列，避免跨仓库死锁）。
  Future<Set<String>> referencedCategoryIdsAsync() async {
    await _ensureLoaded();
    return referencedCategoryIds();
  }
}
