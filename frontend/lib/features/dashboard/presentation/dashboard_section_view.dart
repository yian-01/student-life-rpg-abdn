import 'package:flutter/material.dart';

import '../models/section_state.dart';

/// 分区卡片：按 [SectionState] 渲染加载中/未接入/错误/就绪（契约第 11 节）。
///
/// - loading：显示“加载中”。
/// - notIntegrated：显示“未接入”。
/// - error：显示“加载失败”、错误摘要，并提供 [onRetry] 重试入口。
/// - ready：交给 [contentBuilder]；未提供时显示“暂无数据”。
class DashboardSectionView<T> extends StatelessWidget {
  const DashboardSectionView({
    super.key,
    required this.title,
    required this.state,
    this.contentBuilder,
    this.onRetry,
  });

  final String title;
  final SectionState<T> state;
  final Widget Function(BuildContext context, T data)? contentBuilder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...[_buildBody(context)],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (state.status) {
      case SectionStatus.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                Text('加载中'),
              ],
            ),
          ),
        );
      case SectionStatus.notIntegrated:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('未接入'),
        );
      case SectionStatus.error:
        final error = state.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('加载失败'),
            const SizedBox(height: 4),
            Text(
              '$error',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onRetry != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton(onPressed: onRetry, child: const Text('重试')),
              ),
          ],
        );
      case SectionStatus.ready:
        final data = state.data as T;
        final builder = contentBuilder;
        if (builder == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('暂无数据'),
          );
        }
        return builder(context, data);
    }
  }
}
