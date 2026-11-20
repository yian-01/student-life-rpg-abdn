import 'package:flutter/widgets.dart';

import 'cloud_sync_controller.dart';

class CloudScope extends InheritedNotifier<CloudSyncController> {
  const CloudScope({
    super.key,
    required CloudSyncController controller,
    required super.child,
  }) : super(notifier: controller);

  CloudSyncController get controller => notifier!;

  static CloudSyncController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CloudScope>()?.controller;
}
