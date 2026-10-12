import '../../../shared/repositories/entity_repository.dart';
import '../models/task.dart';

/// H 的任务仓库契约：在通用 [EntityRepository] 之上增加完成状态入口。
/// 消费方（#7 持久化、#12 冲突检测、#14 下游模块）依赖本接口而不是内存实现。
abstract interface class TaskRepository implements EntityRepository<Task> {
  /// 设置完成状态；重复设置相同值保持幂等，不产生奖励副作用。
  Future<void> setCompleted(String id, bool isCompleted);
}
