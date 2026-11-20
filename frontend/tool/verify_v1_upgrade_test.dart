import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

void main() {
  test(
    'V1.0 upgrades an isolated existing-data snapshot without losing fields',
    () async {
      final source = Directory(Platform.environment['V1_UPGRADE_SNAPSHOT']!);
      final folder = await Directory.systemTemp.createTemp('v1-upgrade-audit-');
      addTearDown(() => folder.delete(recursive: true));
      final input = await File('${source.path}/campus.json').readAsString();
      final tasks = await File('${source.path}/tasks.json').readAsBytes();
      final before = jsonDecode(input) as Map<String, dynamic>;
      await File('${folder.path}/campus.json').writeAsString(input);
      await File('${folder.path}/tasks.json').writeAsBytes(tasks);
      final store = CampusStore(
        const FileJsonDocumentStore(),
        '${folder.path}/campus.json',
      );
      await store.initialize();
      final first = await File('${folder.path}/campus.json').readAsString();
      final after = jsonDecode(first) as Map<String, dynamic>;
      if (after['schemaVersion'] != CampusStore.schemaVersion) {
        fail('Unexpected destination schema');
      }
      if (after['scoreScaleMax'] != 5) {
        fail('GPA scale was not migrated');
      }
      for (final table in CampusStore.tables) {
        final original = (before[table] as List? ?? [])
            .cast<Map<String, dynamic>>();
        final actual = (after[table] as List).cast<Map<String, dynamic>>();
        if (original.length != actual.length) {
          fail('Record count changed in $table');
        }
        for (var i = 0; i < original.length; i++) {
          final expected = Map<String, dynamic>.from(original[i]);
          if (table == 'courses' &&
              before['schemaVersion'] != CampusStore.schemaVersion &&
              expected['gradePoint'] != null) {
            expected['gradePoint'] = (expected['gradePoint'] as num) * 5 / 4;
          }
          if (!equals(expected).matches(actual[i], {})) {
            fail('A record changed beyond the defined migration in $table');
          }
        }
      }
      if (before['schemaVersion'] != CampusStore.schemaVersion) {
        if (await File('${folder.path}/campus.json.bak').readAsString() !=
            input) {
          fail('Original backup differs');
        }
      }
      if (!equals(
        tasks,
      ).matches(await File('${folder.path}/tasks.json').readAsBytes(), {})) {
        fail('Tasks changed');
      }
      final reopened = CampusStore(
        const FileJsonDocumentStore(),
        '${folder.path}/campus.json',
      );
      await reopened.initialize();
      if (await File('${folder.path}/campus.json').readAsString() != first) {
        fail('Migration repeated after reopening');
      }
    },
  );
}
