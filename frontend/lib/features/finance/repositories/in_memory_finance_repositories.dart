// ignore_for_file: prefer_initializing_formals

import '../../../shared/repositories/entity_repository.dart';
import '../models/finance_category.dart';
import '../models/finance_record.dart';
import '../models/local_date_time_json.dart';

void _requireId(String id) {
  if (id.trim().isEmpty) {
    throw ArgumentError.value(id, 'id', 'Must not be blank.');
  }
}

DateTime monthStart(int year, int month) {
  if (month < 1 || month > 12) {
    throw ArgumentError.value(month, 'month', 'Must be 1 to 12.');
  }
  return DateTime(year, month);
}

abstract interface class FinanceRecordRepository
    implements EntityRepository<FinanceRecord> {
  Future<List<FinanceRecord>> listForMonth(int year, int month);
}

class InMemoryFinanceCategoryRepository
    implements EntityRepository<FinanceCategory> {
  InMemoryFinanceCategoryRepository({
    required Set<String> Function() referencedCategoryIds,
    Set<String> Function()? budgetReferencedCategoryIds,
  })  : _referencedCategoryIds = referencedCategoryIds,
        _budgetReferencedCategoryIds = budgetReferencedCategoryIds;

  final Map<String, FinanceCategory> _items = {};
  final Set<String> Function() _referencedCategoryIds;
  final Set<String> Function()? _budgetReferencedCategoryIds;

  Set<String> _budgetRefs() => _budgetReferencedCategoryIds?.call() ?? <String>{};

  @override
  Future<List<FinanceCategory>> list() async {
    return List<FinanceCategory>.unmodifiable(
      _items.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
    );
  }

  @override
  Future<FinanceCategory?> getById(String id) async {
    _requireId(id);
    return _items[id];
  }

  @override
  Future<void> insert(FinanceCategory entity) async {
    if (_items.containsKey(entity.id)) {
      throw StateError('Duplicate FinanceCategory id: ${entity.id}');
    }
    final duplicateName = _items.values.any(
      (existing) =>
          existing.type == entity.type &&
          existing.id != entity.id &&
          existing.name.trim().toLowerCase() == entity.name.trim().toLowerCase(),
    );
    if (duplicateName) {
      throw StateError('同类型下已存在同名分类。');
    }
    _items[entity.id] = entity;
  }

  @override
  Future<void> update(FinanceCategory entity) async {
    final existing = _items[entity.id];
    if (existing == null) {
      throw StateError('Unknown FinanceCategory id: ${entity.id}');
    }
    final duplicateName = _items.values.any(
      (other) =>
          other.type == entity.type &&
          other.id != entity.id &&
          other.name.trim().toLowerCase() == entity.name.trim().toLowerCase(),
    );
    if (duplicateName) {
      throw StateError('同类型下已存在同名分类。');
    }
    if (existing.type != entity.type) {
      if (_referencedCategoryIds().contains(entity.id)) {
        throw StateError('该分类被收支记录引用，无法修改类型。');
      }
      if (_budgetRefs().contains(entity.id)) {
        throw StateError('该分类被预算引用，无法修改类型。');
      }
    }
    _items[entity.id] = entity;
  }

  @override
  Future<bool> remove(String id) async {
    _requireId(id);
    if (!_items.containsKey(id)) {
      return false;
    }
    if (_referencedCategoryIds().contains(id)) {
      throw StateError('该分类被收支记录引用，无法删除。');
    }
    if (_budgetRefs().contains(id)) {
      throw StateError('该分类被预算引用，无法删除。');
    }
    _items.remove(id);
    return true;
  }
}

class InMemoryFinanceRecordRepository implements FinanceRecordRepository {
  InMemoryFinanceRecordRepository({
    required EntityRepository<FinanceCategory> categories,
  }) : _categories = categories;

  final Map<String, FinanceRecord> _items = {};
  final EntityRepository<FinanceCategory> _categories;

  Set<String> referencedCategoryIds() =>
      _items.values.map((record) => record.categoryId).toSet();

  @override
  Future<List<FinanceRecord>> list() async {
    return List<FinanceRecord>.unmodifiable(_sorted(_items.values));
  }

  @override
  Future<FinanceRecord?> getById(String id) async {
    _requireId(id);
    return _items[id];
  }

  @override
  Future<void> insert(FinanceRecord entity) async {
    if (_items.containsKey(entity.id)) {
      throw StateError('Duplicate FinanceRecord id: ${entity.id}');
    }
    await _assertCategoryMatches(entity);
    // Re-check after the await: a concurrent insert of the same id may have
    // completed while the category lookup was in flight.
    if (_items.containsKey(entity.id)) {
      throw StateError('Duplicate FinanceRecord id: ${entity.id}');
    }
    _items[entity.id] = entity;
  }

  @override
  Future<void> update(FinanceRecord entity) async {
    if (!_items.containsKey(entity.id)) {
      throw StateError('Unknown FinanceRecord id: ${entity.id}');
    }
    await _assertCategoryMatches(entity);
    // Re-check after the await so a concurrent remove cannot be resurrected.
    if (!_items.containsKey(entity.id)) {
      throw StateError('Unknown FinanceRecord id: ${entity.id}');
    }
    _items[entity.id] = entity;
  }

  @override
  Future<bool> remove(String id) async {
    _requireId(id);
    return _items.remove(id) != null;
  }

  @override
  Future<List<FinanceRecord>> listForMonth(int year, int month) async {
    final start = monthStart(year, month);
    final end = DateTime(year, month + 1);
    final filtered = _items.values.where((record) {
      requireLocalDateTime(record.occurredAt, 'occurredAt');
      return !record.occurredAt.isBefore(start) &&
          record.occurredAt.isBefore(end);
    });
    return List<FinanceRecord>.unmodifiable(_sorted(filtered));
  }

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
      if (byTime != 0) {
        return byTime;
      }
      return a.id.compareTo(b.id);
    });
  }
}
