# Mobile UI revision — 2026-10-31

References inspected:
- https://www.todoist.com/features — task-first information hierarchy and compact
  rows. Its official Android image was inspected, including list grouping,
  restrained accents, a reachable add action and bottom navigation.
- https://ticktick.com/features — reviewed feature page and quick-add examples.
- https://developer.android.com/design/ui/mobile/guides/layout-and-content/layout-basics
  — safe areas, keyboard visibility, reachable primary actions and aligned groups.

The implementation uses original Flutter widgets and Material icons, not copied
brand assets or proprietary code. The bedroom artwork remains the lead's assets.

Whole-app mobile viewport: maximum 430 logical pixels around the Navigator, so
AppBar, page body, FAB, dialogs and navigation share one coordinate space. Smaller
phones use their actual width; layout uses logical pixels, not image resolution.
Windows shows the same mobile layout with neutral outer gutters. MediaQuery size
matches the bounded viewport; keyboard and safe-area insets remain available.

Module UI: light surfaces, indigo primary actions, compact menu rows, five labeled
bottom destinations, selectable week strip and actionable empty state. The bedroom
keeps its explicitly styled scene. Switching modules replaces the current module;
returning to Menu pops to the existing page, preserving the bedroom below it.

No existing repositories, calculators or module services are replaced by this UI
revision. Course/event/assignment/exam integration remains outstanding as recorded
in the functional audit. Demo-data boundaries remain visible.

Review evidence: mobile_ui_review_test covers 360/390/430 logical-pixel phone widths,
a wide Windows-like viewport, module navigation and rendered captures of all module
pages. CI uploads the Flutter renders as mobile-ui-review. These are widget renders,
not Android device screenshots; native safe-area/keyboard/touch acceptance remains
necessary. Linux CI loads Noto CJK for readable review images.
