/// 所有业务模块共用的异步仓库接口。
///
/// list：返回不可修改的列表副本。
/// getById：ID 不存在时返回 null。
/// insert：ID 重复时抛出 StateError。
/// update：ID 不存在时抛出 StateError。
/// remove：删除成功返回 true，ID 不存在返回 false。
///
/// ID 不得为空或全为空白，非法 ID 抛出 ArgumentError。
/// ID 保留原值，不通过 trim 改变实体身份。
/// 存储失败保留原始异常，不得伪装成操作成功或空列表。
abstract interface class EntityRepository<T> {
  Future<List<T>> list();

  Future<T?> getById(String id);

  Future<void> insert(T entity);

  Future<void> update(T entity);

  Future<bool> remove(String id);
}
