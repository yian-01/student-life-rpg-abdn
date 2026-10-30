# Immersive RPG rooms — 2026-10-31

The lead rejected the mixed game/tool-app direction. This revision supersedes the
light UI/bottom-navigation direction in mobile-ui-reference.md.

## Product flow

Bedroom -> campus hall -> four doors -> parchment module -> hall -> bedroom.
The two rooms share RoomScenePage, PlayerMovementController, WalkableArea and
InteractionController. The hall is an actual walkable scene, not clickable cards.
Door signs may be tapped, but InteractionController still enforces player distance.
E, the near-door action and scene-floor taps use the same guarded interaction.

The game view has no AppBar, help footer, bottom navigation or fabricated demo HUD.
Touch controls float over the scene; Windows uses keyboard input and only shows a
near-door action. Android requests portrait immersive-sticky mode. Safe-area insets
apply to controls; the artwork fills underneath them.

SceneTransform.cover uses uniform scaling and a clamped player-following camera.
The existing fit transform remains for legacy geometry/component consumers. A
short/wide viewport crops rather than stretches; walking moves the camera to the
world edges so doors remain reachable. Resizing never mutates world coordinates.

## Hall geometry / asset

Asset: frontend/assets/images/campus_hall_v1.png, 1139 x 1381.
Temporary artwork approved as the basis for continued development; final art
acceptance remains separate. Edited from the lead's supplied image(10).png:
retain its camera and room proportions, furnish the empty floor with a flat
navy/gold rug, a low left console, a right bench and botanical wall pictures.
Screenshot controls were removed. The room was not deliberately resized or
reprojected; generated artwork still requires visual review before final approval.
Programmatic Chinese door signs remain readable and translatable.

Floor polygon: (230,430), (910,430), (1130,1350), (10,1350).
Start: (570,1130). Door approach points: schedule (375,485), GPA (765,485),
Finance (245,680), Dashboard (895,680). Radius 96 world pixels. The same shallow
player ground shape and wider wall clearance from the bedroom are applied.
Obstacles exclude the rear plant, left console/plant and right bench/plant ground
footprints. The rug is walkable. All asset geometry is kept in RoomSpec; replacing
artwork requires remeasuring it, not changing module business logic.

Module routes retain the group's existing controllers, repositories and services.
They render as parchment inside a wood frame over the dim hall background. The
four Chinese panel titles match the door names. No cross-module bottom bar remains.
Task disk persistence / GPA and Finance memory limits are unchanged. Course,
event, assignment and exam application integration is still outstanding.
Task lifecycle/conflict integration and the team module map are recorded in
module-integration-status.md.

## Required verification

- Uniform cover transform, world/local round trip, no internal letterboxing.
- Unobstructed floor path from entry to every door; wall/plant occupancy checks.
- Each door opens only its assigned route and only within range.
- Enter/popup/return keeps the original room instance, position and cleared input.
- Keyboard, joystick release, focus/lifecycle loss and view resizing regressions.
- Flutter captures: bedroom, hall at 360/390/430, desktop mobile viewport and four
  parchment module pages. These do not replace native Android/Windows acceptance.

## Image prompt

Built-in image generation, bedroom image used as style reference only. Prompt:
"Portrait playable pixel-art campus guild hallway; match warm wooden trim, violet
plaster, amber floor and light of the bedroom. Exactly four separated wooden doors,
two on the back wall, two on the side walls; blank signboards for programmatic
labels. Continuous spacious unobstructed central/lower floor, bottom entry path,
wall-shelf plants/books, no characters, UI, text or extra doors. Fill the portrait."
