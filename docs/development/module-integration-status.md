# Module integration status — 2026-10-31

The hall is temporary art. Art acceptance is separate from functional acceptance.
The existing models, repositories and algorithms are being connected to the app;
they are not replaced by the room/UI integration.

## Where the team's work lives

Names below refer to responsibility assignments in docs/project-management/team.md,
not an independent attribution of every line or commit.

| Assigned owner | Existing source under frontend/lib | Application connection / remaining work |
| --- | --- | --- |
| 廖梦溪 | features/bedroom/controllers/player_movement_controller.dart; models/walkable_area.dart | Shared by bedroom and four-door hall, with room-specific geometry |
| 黎宇轩 | features/interaction/controllers/interaction_controller.dart; features/hud/ | Distance-guarded hall doors connected; fabricated demo HUD removed; real progression/rewards still pending |
| 蒋子康 | features/academic/models/, repositories/, services/course_occurrence_service.dart | Course repository used by GPA; actual semester/course management, course occurrences in app Schedule, Assignment/Exam UI/storage still pending |
| 钟顺成 | features/schedule/models/, repositories/, services/day_schedule_service.dart; composition/ | Task reads/writes use one file repository; daily merge and sorting reused; Event model/repository exists but app event entry/persistence pending |
| 郝文聪 | features/schedule/services/conflict_detector.dart; features/gpa/ | GPA connected; conflict detector now consumed by daily task UI; advanced free-slot/splitting/simulation not claimed complete |
| 吴昕玥 | features/finance/ | CRUD, monthly filtering/calculation use existing controller/services; still explicitly in-memory |
| 龙梓瑄 | features/dashboard/models/; features/dashboard/presentation/ | Shared task, GPA and finance summary reads connected; chart scope still pending |
| 李雨真 | shared/storage/; features/schedule/repositories/file_task_repository.dart | JSON task persistence and explicit recovery connected; other entities' durable storage/import/export pending |
| 陈思翰 | app/; features/rooms/; features/bedroom/ | App routing, scene and module integration; native acceptance/build delivery still pending |

## This functional increment

- Task editor supports title, estimate, independent optional deadline and optional
  start/end date-times. Start must precede end; cross-day plans are supported.
- New plans use the selected day, not an unrelated current day. Clearing a plan
  explicitly writes null and returns an incomplete task to the unplanned section.
- Existing tasks can be edited without changing their ID or completion state.
- Completed tasks can be expanded and reopened. Deletion requires confirmation.
- Writes use the existing TaskRepository and existing file format. Draft stays
  open on save failure and no successful write is reported before it resolves.
- Existing findConflicts uses half-open intervals; adjacent tasks do not conflict.
  Completed tasks are omitted from active conflicts. Conflicts are advisory and
  never silently move or reject a user's plan.
- No new reward/EXP or automatic scheduling semantics were invented.

## Verification

Static analysis, formatting and whitespace checks passed locally. New tests cover
file repository reopening after edits/cross-day planning/clearing/deletion,
conflict refresh after completion, editor create/edit, reopening completed tasks,
confirmation, failed save/retry and invalid time ranges. Actual CI results must be
recorded in the PR. Native Android/Windows interaction acceptance remains pending.

Mobile render tests include the daily conflict notice and the expanded task editor
at 390 logical pixels; existing keyboard/high-density tests remain required.
