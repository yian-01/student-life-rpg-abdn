/// Dashboard 分区状态（契约第 11 节）。
///
/// - loading：正在加载，不携带数据或错误。
/// - ready：加载成功，必须携带数据。
/// - notIntegrated：对应回调为 null，显示“未接入”，不携带数据或错误。
/// - error：加载失败，必须携带错误对象。
enum SectionStatus { loading, ready, notIntegrated, error }

/// 单个分区的状态与数据。
///
/// 契约第 15 节：ready 必须携带 data；error 必须携带 error；
/// loading/notIntegrated 不携带伪造数据。空记录不能伪装为“未接入”。
class SectionState<T> {
  /// 正在加载。
  const SectionState.loading()
    : status = SectionStatus.loading,
      data = null,
      error = null;

  /// 依赖模块尚未接入。
  const SectionState.notIntegrated()
    : status = SectionStatus.notIntegrated,
      data = null,
      error = null;

  /// 加载成功；[data] 不得为 null。
  SectionState.ready(T this.data) : status = SectionStatus.ready, error = null {
    if (data == null) {
      throw ArgumentError('SectionState.ready 必须携带数据。');
    }
  }

  /// 加载失败；[error] 由非空参数类型保证必须携带。
  SectionState.failure(Object this.error)
    : status = SectionStatus.error,
      data = null;

  final SectionStatus status;

  /// ready 状态携带的领域数据；其他状态为 null。
  final T? data;

  /// error 状态携带的错误对象；其他状态为 null。
  final Object? error;

  bool get isLoading => status == SectionStatus.loading;
  bool get isReady => status == SectionStatus.ready;
  bool get isNotIntegrated => status == SectionStatus.notIntegrated;
  bool get isError => status == SectionStatus.error;

  @override
  bool operator ==(Object other) =>
      other is SectionState<T> &&
      other.status == status &&
      other.data == data &&
      other.error == error;

  @override
  int get hashCode => Object.hash(status, data, error);

  @override
  String toString() => 'SectionState($status, data: $data, error: $error)';
}
