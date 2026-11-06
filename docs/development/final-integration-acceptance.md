# Application integration acceptance

Scope: responsive dark/gold Menu and module UI, file-backed Tasks, shared-data
Dashboard, unchanged bedroom controls. GPA and Finance remain explicitly in-memory
synthetic demos. No rewards, accounts, cloud sync, or persistent GPA/Finance.

## Data graph

- AppData opens one FileTaskRepository in path_provider's application-support
  directory, `tasks.json`. Directory creation failure is visible and retryable;
  there is no production memory fallback. The app has no seeded Tasks.
- Schedule reads/writes that repository; Dashboard reads the same repository.
- GPA and Dashboard use AppRoutes.gpaComposition and the same calculator.
- Finance and Dashboard use FinanceMemoryScope.shared and its summary service.
- Dashboard refreshes after a child module returns and has a manual refresh.
  Section errors are independent; no failed section becomes a zero total.
- Schedule's restore action requires confirmation, reloads the disk and uses the
  repository's validated backup recovery. Recovery never replays a failed edit.
  If no valid backup is available, files remain untouched and an error is shown.
- GPA/Finance edits survive page navigation in a running app, but reset on a full
  process restart. Bedroom HUD is explicitly demo input.

## Automated evidence

Run in frontend: `flutter pub get`, `dart format --output=none --set-exit-if-changed lib test`,
`flutter analyze`, `flutter test`. Existing tests remain required. New tests cover
file-backed repository reconstruction/completion persistence, Dashboard shared-data
refresh and section error isolation, and Menu bounds with enlarged text at
240x320, 390x844 and 1600x900.

Do not record tests as passed until actual output is available.

## Windows acceptance (pending)

1. Open the latest integration commit. Inspect Menu at a normal and maximized
   window. Four icon cards, bounded width and consistent colors; no giant buttons.
2. Open all modules and resize. Check readable inputs, back navigation, scrolling,
   and no overflow. Regression-check bedroom movement and wall following.
3. Add a uniquely named Task; mark it complete. Verify Dashboard counts. Open
   Schedule from Dashboard, add another task, return; totals update.
4. Fully quit the process and relaunch. Both Tasks and completion remain. A hot
   reload or returning from Menu does not qualify as a restart test.
5. Edit a GPA demo grade; confirm the all-semester Dashboard GPA matches the GPA
   page with the all-semester selection. Add a Finance record dated this month;
   verify Dashboard matches the Finance page for the same month.
6. Restart: Task remains; GPA/Finance reset as labeled.
7. For fault testing, use a separate application data directory/backup. Never
   deliberately corrupt a user's only data. Confirm failed writes report failure
   and validated recovery preserves the corrupt original.

## Android acceptance (pending)

Use an emulator or device: verify portrait, bounded joystick, door interaction,
Menu cards, module navigation, keyboard-open forms and Android back button. Repeat
Task full-process restart test. Check rotation behavior and resume without held
movement input. Desktop verification does not substitute for these checks.

## Native builds

After automated checks pass, run the `Native acceptance builds` workflow on the
integration branch. It provides the entire Windows Release directory (keep all
DLL/data files together) and an Android release APK. The Android project currently
uses its existing debug signing configuration for release builds: this is an
acceptance build, not an app-store distribution signing setup. Native acceptance
is still required after downloading the artifacts. No hosting/publishing is part
of this change.

## Completion gate

Keep the PR in draft until CI passes and the lead accepts the actual Menu/module
visuals, Windows restart behavior and Android native flows. Record SHA, environment,
results and remaining limitations; merge alone is not acceptance.

## Local verification — 2026-10-30

- Dependency resolution completed; path_provider and its platform dependencies
  are locked in pubspec.lock.
- Standalone Dart analyzer: no issues. Dart format and git diff whitespace checks
  passed. These are not a Flutter test execution.
- A real-file smoke check passed: reconstruction preserves Task completion;
  Dashboard metric calculation agrees; corrupt runtime documents reject writes
  without changing original/backup; explicit recovery archives the corrupt
  document and permits a persisted retry.
- Full Flutter widget/test suite, CI and native visual acceptance remain pending.
- Initial remote push was blocked pending authorization. The lead subsequently
  explicitly authorized pushing the changes. CLI credentials are unavailable;
  publishing proceeds through the connected GitHub integration.
