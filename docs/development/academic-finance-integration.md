# Academic, event and finance integration — 2026-11-02

Scope: the lead requested two increments: connect semester/course/event management
and daily course occurrences, and persist academic/finance data locally. This is
not the reward/progression or final native-release milestone. Hall art is unchanged.

## Application journeys

- Hall academic door -> GPA -> Manage semesters/courses. Create a semester with
  inclusive start/end dates and its week-1 Monday. Create/edit/delete courses with
  credits, nullable grade point and zero or multiple weekly slots. Referenced
  semesters cannot be deleted. Course edits preserve course identity.
- Hall schedule door -> courses + events + tasks merged by the existing
  DayScheduleService. The existing occurrencesForDate applies semester boundaries,
  weekday and explicit week numbers; the existing findConflicts handles overlaps.
  Manage events from the schedule toolbar; add/edit/cancel/delete and return
  without changing the selected date. Overnight events retain both dates.
- GPA edits and Dashboard read the same persisted course repository. Points use
  an explicitly labeled custom 4.0 scale, not an invented official school mapping.
  Zero is a valid grade; ungraded courses are excluded from weighted GPA.
- Hall finance door -> standard editable record form, month switching, record
  edit/delete. Default categories are ordinary categories, not seeded transactions.
  Dashboard uses the same record repository and summary service. No fictitious
  budget is supplied. A committed insert is not retried just because refresh fails.
- Editors retain their inputs on failed saves and prevent duplicate submissions.
  Delete actions require confirmation. Restore actions explain backup limitations.

## Data and dependencies

Presentation -> ChangeNotifier controller -> EntityRepository -> CampusStore ->
JsonDocumentStore. App composition supplies controllers/repositories; the original
academic, task, event, money, GPA and conflict models/calculators are reused.
Standalone in-memory/demo compositions remain for isolated tests, not app routes.

AppData opens one CampusData graph lazily in path_provider's application-support
folder. No storage failure falls back to a production memory repository.

Existing tasks.json is untouched. New campus.json schemaVersion=1 stores:
entityType=CampusData, scoreScaleMax=4.0, semesters, courses, events, categories,
records. The JSON decoder checks exact root/entity keys, individual model rules,
unique IDs per table, semester references and category/type references.
There is no migration of old GPA/finance demos: those were never durable data.

All related entities share one serialized transaction queue and one document;
parent/child validation and commit happen in the same queue. Candidate data is
validated and written before becoming the committed in-memory snapshot. Concurrent
inserts cannot lose each other's changes. A stale instance refuses to overwrite
another instance's document; explicit reload resolves it. Course expansion reads
semester/course data from one snapshot.

FileJsonDocumentStore retains its existing temp+flush+backup replacement. A bad or
missing main with a backup is not silently treated as a new empty database.
Routine mutations validate disk and reject corruption or unexpected replacement.
Explicit recovery validates the backup first, archives damaged main as .corrupt
(or a numbered suffix), restores it, and keeps a visible failure if recovery fails.
A backup can omit the last operation; users are told to inspect restored data.

Academic management, event management and finance expose confirmed recovery;
failed initial opening also exposes retry and recovery. Task recovery keeps its
existing separate file-specific confirmation.

## Verification and acceptance

Local Dart format/analyze and a real-file smoke check passed: reopen preserves
zero grade; referenced semester deletion is blocked; corrupted disk refuses normal
writes; explicit recovery retains the damaged original. These are not native tests.

Added tests cover cold repository reopen of semester/course/grade/event/record,
finance edit/delete and summaries, weekday/week/boundary expansion, overnight
items, conflicts, reference/type protections, failed writes without cache changes,
duplicate/concurrent operations, stale instance protection, missing/bad main and
backup, exact schema and parser input limits. Route-level tests create academic
data, return to GPA/schedule, add events, check failed finance input and Dashboard,
and exercise small keyboard-open forms. CI evidence is recorded in PR #28.

Native acceptance remains required:
1. On Android and Windows, create a semester/course with one real slot and a grade.
2. Check that matching dates show the course and non-matching weeks do not.
3. Add and edit an overnight event, check both days and conflict display.
4. Enter income/expense, edit category/date/amount and inspect the matching month.
5. Close the process completely, relaunch, inspect all data and Dashboard totals.
6. Exercise back, keyboard/touch, cancel, small screens and safe areas.
7. Test recovery only with an isolated copied data directory; preserve real data.

Remaining outside this increment: Assignment/Exam app CRUD, reward ledger/EXP/
coins/levels, budgets, advanced scheduling, cloud sync, final art and native
installer/device acceptance. No whole-version completion is claimed.
