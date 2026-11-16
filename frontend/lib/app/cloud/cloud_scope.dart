import 'package:flutter/widgets.dart';

import 'cloud_sync_controller.dart';

class CloudScope extends InheritedWidget {
  const CloudScope({super.key, required this.controller, required super.child});

  final CloudSyncController controller;

  static CloudSyncController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CloudScope>()?.controller;

  @override
  bool updateShouldNotify(CloudScope oldWidget) =>
      oldWidget.controller != controller;
}
