import 'dart:async';

import 'package:student_life_rpg/features/finance/models/finance_category.dart';
import 'package:student_life_rpg/shared/repositories/entity_repository.dart';

/// Decorator that blocks each `getById` call until the test releases it, so
/// interleavings inside the record repository can be driven deterministically
/// instead of relying on timing.
class ControllableCategoryRepository
    implements EntityRepository<FinanceCategory> {
  ControllableCategoryRepository(this._delegate);

  final EntityRepository<FinanceCategory> _delegate;
  final List<Completer<void>> _gates = [];
  bool _autoRelease = false;
  Object? _failure;

  /// Number of `getById` calls observed so far.
  int get getByIdCalls => _gates.length;

  /// Make subsequent lookups complete immediately.
  void autoRelease() => _autoRelease = true;

  /// Block subsequent lookups again so each one waits for its gate.
  void block() => _autoRelease = false;

  /// Make subsequent lookups fail with [error] once released.
  void failWith(Object error) => _failure = error;

  /// Gate for the `getById` call at [index]; complete it to let that lookup
  /// proceed to its answer.
  Completer<void> gateAt(int index) => _gates[index];

  /// Wait until [count] lookups are blocked, then release every gate that has
  /// been registered so far.
  Future<void> reach(int count) async {
    while (_gates.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
    for (final gate in _gates) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  @override
  Future<List<FinanceCategory>> list() => _delegate.list();

  @override
  Future<FinanceCategory?> getById(String id) async {
    if (_autoRelease) {
      return _answer(id);
    }
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    return _answer(id);
  }

  Future<FinanceCategory?> _answer(String id) async {
    final failure = _failure;
    if (failure != null) {
      _failure = null;
      throw failure;
    }
    return _delegate.getById(id);
  }

  @override
  Future<void> insert(FinanceCategory entity) => _delegate.insert(entity);

  @override
  Future<void> update(FinanceCategory entity) => _delegate.update(entity);

  @override
  Future<bool> remove(String id) => _delegate.remove(id);
}
