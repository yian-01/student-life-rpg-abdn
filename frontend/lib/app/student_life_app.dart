import 'dart:async';

import 'package:flutter/material.dart';

import 'app_routes.dart';
import 'atmosphere.dart';
import 'app_theme.dart';
import 'app_viewport.dart';
import 'cloud/cloud_page.dart';
import 'cloud/cloud_scope.dart';
import 'cloud/cloud_sync_controller.dart';
import 'garden/garden_frame.dart';
import 'garden/garden_routes.dart';
import 'garden/garden_settings.dart';
import 'garden/garden_theme.dart';

class StudentLifeApp extends StatefulWidget {
  const StudentLifeApp({
    super.key,
    this.initialRoute = AppRoutes.home,
    this.cloud,
    this.openAccountPage = false,
  });

  final String initialRoute;
  final CloudSyncController? cloud;
  final bool openAccountPage;

  @override
  State<StudentLifeApp> createState() => _StudentLifeAppState();
}

class _StudentLifeAppState extends State<StudentLifeApp> {
  int? _scope;
  _CloudRouteObserver? _observer;
  bool _reopenAccountPage = false;
  Timer? _poll;
  AppLifecycleListener? _lifecycle;
  final _garden = GardenSettings();
  late final ValueNotifier<String> _gardenRoute;
  final _popup = ValueNotifier(false);
  late GardenRouteObserver _gardenObserver;
  GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _gardenRoute = ValueNotifier(widget.initialRoute);
    _gardenObserver = GardenRouteObserver(_gardenRoute, _popup);
    _attach();
    _reopenAccountPage = widget.openAccountPage;
  }

  @override
  void didUpdateWidget(StudentLifeApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cloud != widget.cloud) {
      _detach(oldWidget.cloud);
      _attach();
      _resetNavigation();
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
    // Receipt previews use Flutter's process-wide image cache. Replacing the
    // route stack alone leaves their bytes and decoded images cached.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    setState(() {
      _reopenAccountPage = _observer?.isAccountPage ?? false;
      _scope = cloud.scope;
      _observer = _CloudRouteObserver(cloud);
      _resetNavigation();
    });
  }

  void _resetNavigation() {
    // A GlobalKey must also change: otherwise Flutter may reparent the previous
    // account's Navigator and preserve its forms despite the MaterialApp key.
    _navigator = GlobalKey<NavigatorState>();
    _gardenRoute.value = widget.initialRoute;
    _popup.value = false;
    _gardenObserver = GardenRouteObserver(_gardenRoute, _popup);
    _garden.sound = false;
  }

  void _detach(CloudSyncController? cloud) {
    cloud?.removeListener(_scopeChanged);
    _poll?.cancel();
    _lifecycle?.dispose();
    _scope = null;
    _observer = null;
    _reopenAccountPage = false;
  }

  @override
  void dispose() {
    _detach(widget.cloud);
    _garden.dispose();
    _gardenRoute.dispose();
    _popup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = widget.cloud;
    final observer = _observer;
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1000;
        return ListenableBuilder(
          listenable: _garden,
          builder: (context, _) {
            final app = MaterialApp(
              key: ValueKey(_scope),
              title: '课屿 · 校园生活',
              debugShowCheckedModeBanner: false,
              navigatorKey: _navigator,
              theme: desktop
                  ? GardenTheme.forBrightness(Brightness.light)
                  : AppTheme.light,
              darkTheme: desktop
                  ? GardenTheme.forBrightness(Brightness.dark)
                  : null,
              themeMode: desktop ? _garden.theme : ThemeMode.light,
              navigatorObservers: [_gardenObserver, ?observer],
              builder: (context, child) {
                final content = desktop
                    ? Overlay.wrap(
                        child: GardenFrame(
                          settings: _garden,
                          route: _gardenRoute,
                          popup: _popup,
                          navigator: _navigator,
                          child: child ?? const SizedBox.shrink(),
                        ),
                      )
                    : AppViewport(
                        child: AtmosphereBackdrop(
                          child: child ?? const SizedBox.shrink(),
                        ),
                      );
                return cloud == null
                    ? content
                    : ListenableBuilder(
                        listenable: cloud,
                        child: content,
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
                      );
              },
              initialRoute: widget.initialRoute,
              // Rebuild the route stack so pages cannot retain another account's data.
              onGenerateInitialRoutes: (name) => [
                AppRoutes.generateRoute(RouteSettings(name: name)),
                if (_reopenAccountPage && name != CloudPage.route)
                  AppRoutes.generateRoute(
                    const RouteSettings(name: CloudPage.route),
                  ),
              ],
              onGenerateRoute: AppRoutes.generateRoute,
            );
            return GardenScope(
              settings: _garden,
              desktop: desktop,
              child: cloud == null
                  ? app
                  : CloudScope(controller: cloud, child: app),
            );
          },
        );
      },
    );
  }
}

class _CloudRouteObserver extends NavigatorObserver {
  _CloudRouteObserver(this.cloud);
  final CloudSyncController cloud;
  Route<dynamic>? _top;

  bool get isAccountPage => _top?.settings.name == CloudPage.route;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _top = topRoute;
    final name = topRoute.settings.name;
    final safe =
        name == AppRoutes.home ||
        name == AppRoutes.bedroom ||
        name == AppRoutes.menu ||
        GardenRoutes.hubs.contains(name) ||
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
