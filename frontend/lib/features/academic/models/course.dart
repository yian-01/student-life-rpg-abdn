import 'academic_json.dart';
import 'course_slot.dart';

/// 课程。
///
/// 契约第 5 节字段：
/// `String id、semesterId、name；double credits；double? gradePoint；List<CourseSlot> slots`。
///
/// 校验规则：
/// - `credits` 必须为有限正数。
/// - `gradePoint` 为 null 或有限数，范围为 0 至调用方传入的 [scoreScaleMax]。
/// - 演示显式传入 scoreScaleMax=4.0，明确标注为演示规则，
///   不代表学校官方 GPA 制度。
/// - `slots` 可以为空；演示用课程至少有一个时间段。
///
/// `gradePoint` 的上界依赖评分制，构造和解码必须显式传入 [scoreScaleMax]；
/// GPA 计算仍由 J 的算法按调用方实际传入的 `scoreScaleMax` 再校验一次。
class Course {
  Course({
    required this.id,
    required this.semesterId,
    required this.name,
    required this.credits,
    this.gradePoint,
    required List<CourseSlot> slots,
    required double scoreScaleMax,
  }) : slots = List<CourseSlot>.unmodifiable(slots) {
    validateNotBlank(id, 'id');
    validateNotBlank(semesterId, 'semesterId');
    validateNotBlank(name, 'name');

    if (!credits.isFinite || credits <= 0) {
      throw ArgumentError.value(
        credits,
        'credits',
        'Must be a finite positive number.',
      );
    }
    if (!scoreScaleMax.isFinite || scoreScaleMax <= 0) {
      throw ArgumentError.value(
        scoreScaleMax,
        'scoreScaleMax',
        'Must be a finite positive number.',
      );
    }
    final point = gradePoint;
    if (point != null) {
      if (!point.isFinite) {
        throw ArgumentError.value(point, 'gradePoint', 'Must be finite.');
      }
      if (point < 0 || point > scoreScaleMax) {
        throw ArgumentError.value(
          point,
          'gradePoint',
          'Must be between 0 and scoreScaleMax.',
        );
      }
    }
  }

  static const Set<String> jsonKeys = {
    'id',
    'semesterId',
    'name',
    'credits',
    'gradePoint',
    'slots',
  };

  final String id;
  final String semesterId;
  final String name;
  final double credits;
  final double? gradePoint;

  /// 上课时间段，构造时已复制为不可变列表。
  final List<CourseSlot> slots;

  Map<String, dynamic> toJson() => {
    'id': id,
    'semesterId': semesterId,
    'name': name,
    'credits': credits,
    // 可空字段 toJson 必须写入 null。
    'gradePoint': gradePoint,
    'slots': List<Object?>.unmodifiable(
      slots.map((slot) => slot.toJson()).toList(growable: false),
    ),
  };

  factory Course.fromJson(
    Map<String, dynamic> json, {
    required double scoreScaleMax,
  }) {
    rejectUnknownKeys(json, jsonKeys, context: 'Course');
    final id = readRequiredString(json, 'id');
    final semesterId = readRequiredString(json, 'semesterId');
    final name = readRequiredString(json, 'name');
    final credits = readRequiredDouble(json, 'credits');
    final gradePoint = readNullableDouble(json, 'gradePoint');
    final slotJson = readRequiredObjectList(json, 'slots');

    // 嵌套对象同样拒绝未知键，并由各自模型完成校验。
    final slots = slotJson.map(CourseSlot.fromJson).toList(growable: false);

    return decodeWithArgumentErrors(
      () => Course(
        id: id,
        semesterId: semesterId,
        name: name,
        credits: credits,
        gradePoint: gradePoint,
        slots: slots,
        scoreScaleMax: scoreScaleMax,
      ),
    );
  }
}
