import 'package:flutter_test/flutter_test.dart';
import 'package:student_life_rpg/features/dashboard/models/section_state.dart';

void main() {
  group('SectionState 状态守卫', () {
    test('ready 必须携带数据', () {
      final state = SectionState<String>.ready('数据');
      expect(state.status, SectionStatus.ready);
      expect(state.data, '数据');
      expect(state.error, isNull);
      expect(state.isReady, isTrue);
    });

    test('ready 数据为 null 时拒绝（可空类型实例化）', () {
      expect(() => SectionState<String?>.ready(null), throwsArgumentError);
    });

    test('error 必须携带错误', () {
      final state = SectionState<int>.failure(StateError('boom'));
      expect(state.status, SectionStatus.error);
      expect(state.error, isA<StateError>());
      expect(state.data, isNull);
      expect(state.isError, isTrue);
    });

    test('error 由非空参数类型保证必须携带错误', () {
      final state = SectionState<int>.failure(StateError('boom'));
      expect(state.error, isNotNull);
    });

    test('loading 与 notIntegrated 不携带数据或错误', () {
      const loading = SectionState<int>.loading();
      expect(loading.status, SectionStatus.loading);
      expect(loading.data, isNull);
      expect(loading.error, isNull);
      expect(loading.isLoading, isTrue);

      const notIntegrated = SectionState<int>.notIntegrated();
      expect(notIntegrated.status, SectionStatus.notIntegrated);
      expect(notIntegrated.data, isNull);
      expect(notIntegrated.error, isNull);
      expect(notIntegrated.isNotIntegrated, isTrue);
    });

    test('相同状态与数据相等，不同状态不等', () {
      expect(SectionState<int>.ready(1), SectionState<int>.ready(1));
      expect(SectionState<int>.ready(1), isNot(SectionState<int>.loading()));
      expect(
        const SectionState<int>.loading(),
        const SectionState<int>.loading(),
      );
      final error = StateError('x');
      expect(
        SectionState<int>.failure(error),
        SectionState<int>.failure(error),
      );
    });
  });
}
