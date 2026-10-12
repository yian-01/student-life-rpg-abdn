import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/schedule/models/event.dart';
import 'package:student_life_rpg/shared/models/time_range.dart';

void main() {
  group('Event', () {
    final range = TimeRange(
      start: DateTime(2026, 10, 5, 9, 0),
      end: DateTime(2026, 10, 5, 10, 0),
    );

    test('has no task completion state and supports nullable description', () {
      final event = Event(id: 'event-1', title: 'Team meeting', range: range);
      final restored = Event.fromJson(event.toJson());

      expect(event.description, isNull);
      expect(restored, event);
    });

    test('copyWith can clear description without changing id', () {
      final event = Event(
        id: 'event-1',
        title: 'Team meeting',
        range: range,
        description: 'Weekly sync',
      );

      final cleared = event.copyWith(description: null);
      expect(cleared.id, event.id);
      expect(cleared.description, isNull);
    });

    test('rejects invalid required fields', () {
      expect(
        () => Event(id: '', title: 'Event', range: range),
        throwsArgumentError,
      );
      expect(
        () => Event(id: 'event-1', title: '', range: range),
        throwsArgumentError,
      );
    });

    test('JSON reader rejects UTC and offset date-times', () {
      final base = <String, dynamic>{
        'id': 'event-1',
        'title': 'Team meeting',
        'description': null,
      };

      expect(
        () => Event.fromJson({
          ...base,
          'range': {
            'start': '2026-10-05T09:00:00Z',
            'end': '2026-10-05T10:00:00.000',
          },
        }),
        throwsFormatException,
      );
      expect(
        () => Event.fromJson({
          ...base,
          'range': {
            'start': '2026-10-05T09:00:00.000',
            'end': '2026-10-05T10:00:00+08:00',
          },
        }),
        throwsFormatException,
      );
    });

    test('JSON reader rejects unknown fields at model and nested level', () {
      expect(
        () => Event.fromJson({
          'id': 'event-1',
          'title': 'Team meeting',
          'range': {
            'start': '2026-10-05T09:00:00',
            'end': '2026-10-05T10:00:00',
          },
          'location': 'A101',
          'description': null,
        }),
        throwsFormatException,
      );
      expect(
        () => Event.fromJson({
          'id': 'event-1',
          'title': 'Team meeting',
          'range': {
            'start': '2026-10-05T09:00:00',
            'end': '2026-10-05T10:00:00',
            'extra': true,
          },
          'description': null,
        }),
        throwsFormatException,
      );
    });

    test('JSON reader rejects a reversed range', () {
      expect(
        () => Event.fromJson({
          'id': 'event-1',
          'title': 'Team meeting',
          'range': {
            'start': '2026-10-05T10:00:00',
            'end': '2026-10-05T09:00:00',
          },
          'description': null,
        }),
        throwsFormatException,
      );
    });
  });
}
