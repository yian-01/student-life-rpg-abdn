import 'dart:async';

import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'app_theme.dart';
import 'app_viewport.dart';
import 'cloud/cloud_page.dart';
import 'cloud/cloud_scope.dart';
import 'cloud/cloud_sync_controller.dart';

class StudentLifeApp extends StatefulWidget {
  const StudentLifeApp({
    super.key,
    this.initialRoute = AppRoutes.bedroom,
    this.cloud,
  });

  final String initialRoute;
  final CloudSyncController? cloud;

  @override
  State<StudentLifeApp> createState() => _StudentLifeAppState();
}

class _StudentLifeAppState extends State<StudentLifeApp> {
  int? _scope;
  _CloudRouteObserver? _observer;
  Timer? _poll;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(StudentLifeApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cloud != widget.cloud) {
      _detach(oldWidget.cloud);
      _attach();
    }
  }

  void _attach() {
    final cloud = widget.cloud;
    if (cloud == null) return;
    _scope = cloud.scope;
    _observer = _CloudRouteObserver(cloud);
    cloud.addListener(_scopeChanged);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => cloud.lifecycleChanged(
        foreground: state == AppLifecycleState.resumed,
      ),
    );
    _poll = Timer.periodic(
      const Duration(seconds: 25),
      (_) => unawaited(cloud.autoSync()),
    );
  }

  void _scopeChanged() {
    final cloud = widget.cloud!;
    if (_scope == cloud.scope) return;
    setState(() {
      _scope = cloud.scope;
      _observer = _CloudRouteObserver(cloud);
    });
  }

  void _detach(CloudSyncController? cloud) {
    cloud?.removeListener(_scopeChanged);
    _poll?.cancel();
    _lifecycle?.dispose();
    _scope = null;
    _observer = null;
  }

  @override
  void dispose() {
    _detach(widget.cloud);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = widget.cloud;
    final observer = _observer;
    final app = MaterialApp(
      key: ValueKey(_scope),
      title: 'Student Life RPG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorObservers: [?observer],
      builder: (context, child) => AppViewport(
        child: cloud == null
            ? child ?? const SizedBox.shrink()
            : ListenableBuilder(
                listenable: cloud,
                child: child,
                builder: (context, child) => Stack(
                  fit: StackFit.expand,
                  children: [
                    child ?? const SizedBox.shrink(),
                    if (cloud.applying)
                      const ModalBarrier(
                        color: Colors.transparent,
                        dismissible: false,
                      ),
                  ],
                ),
              ),
      ),
      initialRoute: widget.initialRoute,
      // Start with one root page, without an implicit '/' underneath.
      onGenerateInitialRoutes: (name) => [
        AppRoutes.generateRoute(RouteSettings(name: name)),
      ],
      onGenerateRoute: AppRoutes.generateRoute,
    );
    return cloud == null ? app : CloudScope(controller: cloud, child: app);
  }
}

class _CloudRouteObserver extends NavigatorObserver {
  _CloudRouteObserver(this.cloud);
  final CloudSyncController cloud;
  Route<dynamic>? _top;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _top = topRoute;
    final name = topRoute.settings.name;
    final safe =
        name == AppRoutes.bedroom ||
        name == AppRoutes.menu ||
        name == CloudPage.route;
    cloud.routeChanged(safe: safe);
    // A dialog may have returned a confirmation to an action on this page.
    // Do not start a competing sync while that action resumes.
    if (!safe || previousTopRoute is PopupRoute) return;
    final scope = cloud.scope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator?.mounted != true ||
          _top != topRoute ||
          cloud.scope != scope) {
        return;
      }
      unawaited(cloud.autoSync());
    });
  }
}
