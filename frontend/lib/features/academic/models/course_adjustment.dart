import '../../../shared/models/time_range.dart';
import 'academic_json.dart';

/// An exception anchored to the original occurrence, even after moving it.
class CourseAdjustment {
  CourseAdjustment({
    required this.occurrenceId,
    required this.original,
    required this.replacement,
    this.location,
  }) {
    validateNotBlank(occurrenceId, 'occurrenceId');
    if (replacement == null && location != null) {
      throw ArgumentError('A cancelled class has no replacement location.');
    }
  }

  final String occurrenceId;
  final TimeRange original;
  final TimeRange? replacement;
  final String? location;

  Map<String, dynamic> toJson() => {
    'occurrenceId': occurrenceId,
    'original': original.toJson(),
    'replacement': replacement?.toJson(),
    'location': location,
  };

  factory CourseAdjustment.fromJson(Map<String, dynamic> json) {
    rejectUnknownKeys(json, const {
      'occurrenceId',
      'original',
      'replacement',
      'location',
    }, context: 'CourseAdjustment');
    TimeRange readRange(Object? value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid course adjustment time range');
      }
      return TimeRange.fromJson(value);
    }

    return decodeWithArgumentErrors(
      () => CourseAdjustment(
        occurrenceId: readRequiredString(json, 'occurrenceId'),
        original: readRange(json['original']),
        replacement: json['replacement'] == null
            ? null
            : readRange(json['replacement']),
        location: readNullableString(json, 'location'),
      ),
    );
  }
}
