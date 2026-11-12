import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../shared/models/schedule_item.dart';

Uint8List exportCalendar(Iterable<ScheduleItem> items, DateTime generatedAt) {
  final unique =
      {
        for (final item in items) (item.sourceType, item.id): item,
      }.values.toList()..sort((a, b) {
        final byDate = a.range.start.compareTo(b.range.start);
        return byDate == 0 ? a.id.compareTo(b.id) : byDate;
      });
  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Student Life RPG//Schedule Export//ZH',
    'CALSCALE:GREGORIAN',
    for (final item in unique) ..._event(item, generatedAt),
    'END:VCALENDAR',
  ];
  return Uint8List.fromList(
    utf8.encode('${lines.map(_fold).join('\r\n')}\r\n'),
  );
}

Iterable<String> _event(ScheduleItem item, DateTime generatedAt) sync* {
  final uid = sha256.convert(
    utf8.encode('${item.sourceType.name}\u0000${item.id}'),
  );
  final end = item.range.end;
  final fractional = end.millisecond * 1000 + end.microsecond;
  final roundedEnd = fractional == 0
      ? end
      : end.add(Duration(microseconds: 1000000 - fractional));
  yield 'BEGIN:VEVENT';
  yield 'UID:$uid@student-life-rpg.local';
  yield 'DTSTAMP:${_utc(generatedAt)}';
  yield 'DTSTART:${_utc(item.range.start)}';
  yield 'DTEND:${_utc(roundedEnd)}';
  yield 'SUMMARY:${_text(item.title)}';
  if (item.location case final location?) yield 'LOCATION:${_text(location)}';
  yield 'END:VEVENT';
}

String _utc(DateTime time) {
  final date = time.toUtc();
  if (date.year < 1 || date.year > 9999) {
    throw const FormatException('日历导出支持 1 到 9999 年。');
  }
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}${two(date.month)}${two(date.day)}'
      'T${two(date.hour)}${two(date.minute)}${two(date.second)}Z';
}

String _text(String text) => text
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
    .replaceAll(r'\', r'\\')
    .replaceAll(RegExp(r'\r\n?|\n'), r'\n')
    .replaceAll(',', r'\,')
    .replaceAll(';', r'\;');

String _fold(String line) {
  final result = StringBuffer();
  var length = 0;
  for (final rune in line.runes) {
    final character = String.fromCharCode(rune);
    final bytes = utf8.encode(character).length;
    if (length + bytes > 75) {
      result.write('\r\n ');
      length = 1;
    }
    result.write(character);
    length += bytes;
  }
  return result.toString();
}
