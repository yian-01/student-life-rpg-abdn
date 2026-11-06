import 'package:flutter/foundation.dart';
import '../../../shared/repositories/entity_repository.dart';
import '../models/event.dart';

class EventController extends ChangeNotifier {
  EventController(this.repository);
  final EntityRepository<Event> repository;
  List<Event> events = const [];
  bool _disposed = false;
  Future<void> load() async {
    final values = (await repository.list()).toList()
      ..sort((a, b) => a.range.start.compareTo(b.range.start));
    if (_disposed) return;
    events = List.unmodifiable(values);
    notifyListeners();
  }

  Future<void> save(Event event, {required bool creating}) =>
      creating ? repository.insert(event) : repository.update(event);
  Future<void> remove(String id) async {
    if (!await repository.remove(id)) throw StateError('Unknown event');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
