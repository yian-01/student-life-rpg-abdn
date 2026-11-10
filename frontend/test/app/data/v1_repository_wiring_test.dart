import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/app/data/campus_data.dart';
import 'package:student_life_rpg/app/data/campus_store.dart';
import 'package:student_life_rpg/features/academic/models/assignment.dart';
import 'package:student_life_rpg/features/academic/repositories/assignment_repository.dart';
import 'package:student_life_rpg/features/academic/repositories/exam_repository.dart';
import 'package:student_life_rpg/features/finance/models/budget.dart';
import 'package:student_life_rpg/features/finance/models/finance_record.dart';
import 'package:student_life_rpg/features/finance/models/finance_type.dart';
import 'package:student_life_rpg/features/finance/repositories/campus_budget_repository.dart';
import 'package:student_life_rpg/shared/storage/json_document_store.dart';

void main() {
  test(
    'application wiring persists assignments and category budgets together',
    () async {
      final dir = await Directory.systemTemp.createTemp('v1_wiring_');
      final path = '${dir.path}/campus.json';
      final fixture = await File(
        'test/app/data/fixtures/campus_v1_fixture.json',
      ).readAsString();
      await File(path).writeAsString(fixture);
      CampusData open() =>
          CampusData(CampusStore(const FileJsonDocumentStore(), path));
      final first = open();
      final second = open();
      try {
        expect(first.assignments, isA<StoredAssignmentRepository>());
        expect(first.exams, isA<StoredExamRepository>());
        expect(first.budgets, isA<CampusBudgetRepository>());
        await first.assignments.insert(
          Assignment(
            id: 'wire-assignment',
            courseId: 'course-cs101',
            title: '持久化作业',
            dueAt: DateTime(2026, 11, 20, 18),
          ),
        );
        await first.budgets.put(
          Budget(
            categoryId: 'food',
            month: DateTime(2026, 11),
            amountMinor: 10000,
          ),
        );
        expect(
          (await second.assignments.getById('wire-assignment'))?.title,
          '持久化作业',
        );
        await second.budgetController.load(month: DateTime(2026, 11));
        expect(second.budgetController.budgetFor('food'), 10000);

        await second.records.insert(
          FinanceRecord(
            id: 'wire-expense',
            categoryId: 'food',
            type: FinanceType.expense,
            amountMinor: 3550,
            occurredAt: DateTime(2026, 11, 5, 12),
          ),
        );
        final summary = await second.financeService.loadMonth(
          DateTime(2026, 11),
        );
        expect(summary.budgetMinor, 10000);
        expect(summary.remainingBudgetMinor, 6450);
        expect(summary.expenseByCategory.single.amountMinor, 3550);

        await expectLater(
          second.courses.remove('course-cs101'),
          throwsStateError,
        );
        expect((await second.courses.getById('course-cs101')), isNotNull);
      } finally {
        first.dispose();
        second.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
