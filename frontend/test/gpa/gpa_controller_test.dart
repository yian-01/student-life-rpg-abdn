import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/shared/repositories/entity_repository.dart';
import 'package:student_life_rpg/features/academic/models/course.dart';
import 'package:student_life_rpg/features/gpa/controllers/gpa_controller.dart';
import 'package:student_life_rpg/features/gpa/composition/gpa_composition.dart';
import 'gpa_calculator_test.dart' show course;

class ControlledRepository implements EntityRepository<Course> {
  List<Course> items = [course('a', point: 4), course('b', semester: 'other')];
  Object? failure;
  Object? writeFailure;
  Future<List<Course>> Function()? onList;
  @override
  Future<List<Course>> list() async {
    if (failure != null) throw failure!;
    return onList == null ? List.unmodifiable(items) : onList!();
  }

  @override
  Future<Course?> getById(String id) async =>
      items.where((c) => c.id == id).firstOrNull;
  @override
  Future<void> update(Course entity) async {
    if (writeFailure != null) throw writeFailure!;
    items[items.indexWhere((c) => c.id == entity.id)] = entity;
  }

  @override
  Future<void> insert(Course entity) async => items.add(entity);
  @override
  Future<bool> remove(String id) async => throw UnimplementedError();
}

void main() {
  test(
    'load exposes loading, filters before calculation and retry keeps selection',
    () async {
      final repo = ControlledRepository();
      final controller = GpaController(
        courseRepository: repo,
        scoreScaleMax: 4,
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final pending = controller.load(semesterId: 'other');
      expect(controller.isLoading, isTrue);
      await pending;
      expect(controller.result!.value, isNull);
      expect(controller.result!.missingCount, 1);
      expect(controller.courses.single.id, 'b');
      expect(controller.semesterIds, ['other', 's']);
      final failure = StateError('read failed');
      repo.failure = failure;
      await controller.retry();
      expect(controller.error, same(failure));
      expect(controller.result, isNull);
      expect(controller.isLoading, isFalse);
      repo.failure = null;
      await controller.retry();
      expect(controller.error, isNull);
      expect(controller.semesterId, 'other');
      expect(notifications, 6);
      expect(() => controller.courses.clear(), throwsUnsupportedError);
    },
  );
  test(
    'only latest request updates state and dispose ignores late completion',
    () async {
      final repo = ControlledRepository();
      final first = Completer<List<Course>>();
      final second = Completer<List<Course>>();
      var count = 0;
      repo.onList = () => count++ == 0 ? first.future : second.future;
      final controller = GpaController(
        courseRepository: repo,
        scoreScaleMax: 4,
      );
      final a = controller.load(semesterId: 's');
      final b = controller.load(semesterId: 'other');
      second.complete(repo.items);
      await b;
      first.completeError(StateError('old failure'));
      await a;
      expect(controller.error, isNull);
      expect(controller.semesterId, 'other');
      final late = Completer<List<Course>>();
      repo.onList = () => late.future;
      final pending = controller.load();
      controller.dispose();
      late.complete(repo.items);
      await pending;
    },
  );
  test(
    'write failure is visible, preserves repository and can recover',
    () async {
      final repo = ControlledRepository();
      final controller = GpaController(
        courseRepository: repo,
        scoreScaleMax: 4,
      );
      addTearDown(controller.dispose);
      await controller.load(semesterId: 's');
      final failure = StateError('write failed');
      repo.writeFailure = failure;
      await controller.setGradePoint('a', 0);
      expect(controller.error, same(failure));
      expect(repo.items.first.gradePoint, 4);
      repo.writeFailure = null;
      await controller.retry();
      await controller.setGradePoint('a', 0);
      expect(controller.result!.value, 0);
      await controller.setGradePoint('a', null);
      expect(controller.result!.value, isNull);
      await controller.setGradePoint('a', 5);
      expect(controller.error, isArgumentError);
      await controller.setGradePoint('missing', 1);
      expect(controller.error, isStateError);
    },
  );
  test('real G repositories and A/N callback observe the same edits', () async {
    final assembly = GpaComposition.inMemoryDemo();
    final controller = await assembly.createController();
    addTearDown(controller.dispose);
    await controller.load(semesterId: '2026秋季');
    expect(controller.result!.value, closeTo(3.7, 1e-9));
    await controller.setGradePoint('demo-english', 0);
    final callbackResult = await assembly.loadGpa(semesterId: '2026秋季');
    expect(callbackResult.value, closeTo(18.5 / 8, 1e-9));
    expect(callbackResult.value, controller.result!.value);
    expect(
      (await assembly.courseRepository.getById('demo-english'))!.gradePoint,
      0,
    );
    await controller.load(semesterId: 'empty');
    expect(controller.result!.gradedCourseCount, 0);
    expect(controller.result!.value, isNull);
    await controller.load(semesterId: ' ');
    expect(controller.error, isArgumentError);
  });
}
