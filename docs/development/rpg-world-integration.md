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

Asset: frontend/assets/images/campus_hall_v1.png, 948 x 1659.
Original generated background, using the existing bedroom as a style reference.
Four wooden doors, violet plaster, amber tiles and warm light. No external brand
assets used. Programmatic Chinese door signs remain readable and translatable.

Floor polygon: (201,655), (746,655), (930,1435), (18,1435).
Start: (474,1260). Door approach points: schedule (320,710), GPA (624,710),
Finance (175,1085), Dashboard (775,1085). Radius 96 world pixels. The same shallow
player ground shape and wider wall clearance from the bedroom are applied; the
central plant and lower corner plants are excluded. Geometry is kept in RoomSpec.

Module routes retain the group's existing controllers, repositories and services.
They render as parchment inside a wood frame over the dim hall background. The
four Chinese panel titles match the door names. No cross-module bottom bar remains.
Task disk persistence / GPA and Finance memory limits are unchanged. Course,
event, assignment and exam application integration is still outstanding.

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
