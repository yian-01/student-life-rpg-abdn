import 'package:flutter/foundation.dart';

/// 玩家档案：当前选择的性别。
///
/// 占位实现——方案②（性别自主选择界面）经组长批复后，这里会改为
/// 从设置/存档读取，并在首次启动或设置页写入。当前默认 'male'，
/// 素材命名前缀即取自本值（player_{gender}_...png）。
///
/// 用 [ValueNotifier] 承载，性别切换后所有监听处（PlayerSprite）
/// 会自动重建。先用内存态，不入库，避免提前引入存档依赖。
class PlayerProfile {
  PlayerProfile._();

  /// 允许的性别取值（与素材文件命名前缀一致）。
  static const Set<String> genders = {'male', 'female'};

  /// 当前性别。默认男生；后续由性别选择界面/存档驱动。
  static final ValueNotifier<String> gender = ValueNotifier<String>('male');

  /// 设置性别（仅接受 [genders] 内的值）。
  static void setGender(String value) {
    if (!genders.contains(value)) {
      throw ArgumentError('unsupported gender: $value');
    }
    gender.value = value;
  }
}
