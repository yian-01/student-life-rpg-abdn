# Issue34 second delivery — 2026-11-06

Fixed base remains e0e38b5. No global routes, shared storage, schedule whole-page edits or dependencies changed.

## Evidence
- Real user-supplied HTML fixture: test/fixtures/issue34/scnu_deidentified.html. Removed name/student number, replaced teachers and class composition, removed opaque data-jxb_id. Retained actual layout/lesson names/class codes/schedules for deterministic replay. Never committed original HTML, password or session data.
- Main worktree: full flutter test 571/571 pass (exit0), flutter analyze No issues found. Added real 22-grid-row replay and independent A13/Exam boundary tests. Default strict reader now detects unscheduled-other section outside grid, fixing real replay discovery.
- #31 exact provider commit 32e15c02e179e79e090b46b3b27e71a81ae68a6e: isolated worktree adapter contract test 1/1 pass, analyze No issues found. Adapter returns actual TimetableParseResult/ParsedCourse/ParsedSlot; no duplicate official models.
- Formal adapter delivered as docs/patches/issue34-formal-preview.patch because official preview files are absent from fixed base. Apply only AFTER provider interfaces are integrated. It is not automatically active in current production app.
- Initial isolated pub get reported Windows symlink/developer-mode prerequisite; Dart/Flutter tests and analysis subsequently executed successfully. No native install/login/keyboard or restart acceptance claimed.

## Adapter call after dependency integration
Apply patch using git apply --check docs/patches/issue34-formal-preview.patch, then git apply. Invoke parseScnuHtml(html, maxWeek: confirmedSemester.lastValidWeek, periods: userConfirmedPeriodTable). HTML only, no URL fetching. Use Semester dates/anchor, not inferred 17-week universal bound. Period11 was user-authorized extrapolation, not independently official.

Preserves preview location and teacher; credits missing stays null. Raw scheduled source identity is scnu + encoded original teaching-class identifier. Adapter ParsedCourse.classCode retains provider's raw class key; source namespace and target semester must be incorporated by #30's final identity contract. Never hashCode for persisted IDs.

Lab A suffix normalization only when an observed theory row of same name and credits has the exact base code. No unconditional suffix stripping. Same-time different-location/week rows retained as distinct preview slots rather than discarding locations. Provider downstream plan normalization still needs review.

## Unfinished / do not mark accepted
- Other unscheduled courses are explicitly surfaced as issues but not yet modeled as saveable courses: original HTML does not expose dependable class ID/credits for this section. Need #31 preview user correction and #30 identity decision. Do not save partial result without displaying/reconciling issues.
- #37 has capture draft only, no real login/capture function. Login/error/empty currently throw FormatException; distinct UI classification remains to integrate with capture contract. No arbitrary HTML/iframe/JSON support promised.
- Batch transaction ST11 interface absent in supplied storage card; no row-by-row writes introduced. No preview cancel/save/restart proof.
- Exam test uses real Exam domain range projected ONLY in test to shared ScheduleItem because production I exam adaptation is absent from fixed baseline; not production exam integration proof.
- A13 guard independently verifies five-week/shortened-semester bounds; does not prove every UI save/storage mutation enforces guard.
- Full storage-upgrade/GPA/Dashboard/native Android+Windows consumer verification remains open.

## Coordination text
#31: adapter patch compiled against your 32e15c0, function parseScnuHtml returning your types; please integrate after source/identity review. Other-course missing identity/credits needs editable preview, not silent drop. Your hashCode IDs and row-wise save examples must not be used for production transaction flow.
#30: raw teaching-class ID plus provider namespace and target semester proposed as source identity; lab parent matching is conditional. Please finalize ST11 contract/identity schema; no persisted field extension made by #34.
#37: HTML string supported for actual kbgrid_table_0; draft document/iframe/response envelope is not a production callable contract yet. Need real host/capture API and classified failure states.
#32: independent conflict_details.dart available from first commit; inject exam display labels by derived ScheduleItem ID. Do not duplicate title-based identities or edit whole page from #34.