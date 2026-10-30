# Bedroom integration — Issue #15

The application route `/bedroom` now consumes the existing C/D/E/F implementations. The two PNG files are reused from the group lead's personal project and are registered explicitly in `frontend/pubspec.yaml`; no image was generated or edited for this integration.

## Composition and input

- `SceneGeometry` is the only source of world dimensions, walkable polygon, sprite anchor and door target. Source dimensions were checked: background 941×1672; sprite 103×205 RGBA.
- `SceneViewport` derives `SceneTransform` from its own constraints, after SafeArea, AppBar and the input panel. Background and sprite use the same transform; pointer positions are already local to this viewport and are not converted twice. Letterbox input is ignored by the interaction controller.
- `BedroomPage` owns its default movement controller, interaction controller, focus node and ticker. An injected movement controller remains externally owned. The ticker stops when input stops, the page loses focus or the app is inactive.
- WASD/arrows and the UI joystick both use the existing movement controller; release/cancel clears direction. The joystick is also available on desktop for manual cross-input checking.
- Near the Menu target, press E, tap the target or use the entry button. A distant key press cannot bypass the shared interaction range. The original unrestricted placeholder shortcut has been removed.
- Navigation awaits the actual pushed route's pop. Movement pauses while covered, retains its world position and returns without held input. Disposal releases all owned resources.
- HUD uses the shared F widget in an unscaled UI layer anchored to sceneRect. Its height is capped to avoid covering the walking area in short viewports. Level/EXP are labelled demo data; no automatic rewards are claimed.
- Android startup requests portrait orientation. Windows retains a resizable window. This setting is not evidence that Android native orientation/input has been accepted.

## Verification

Production-page tests cover asset layout, foot-anchor placement at multiple sizes, keyboard movement, resize stability, guarded navigation, scene pointer/letterbox handling, joystick release, focus loss, app inactivity, small windows with enlarged text and a zero viewport. Existing navigation smoke tests now walk toward the door through the production input adapter.

The current commit's GitHub Actions run is the authoritative evidence for formatting, analysis and tests. Windows native rendering/collision overlay and Android native joystick/orientation remain manual acceptance items.

## Manual acceptance

1. In `frontend/`, run `flutter pub get`, then `flutter run -d windows`.
2. Confirm both images load, the complete room is centred without stretching, and the character is initially on the floor corridor.
3. Hold/release WASD or arrow keys; verify no diagonal speedup, no movement into blocked floor areas and no continued movement after release.
4. Resize the window: the world/character resize together; the character's world location remains unchanged. HUD text and joystick do not scale with the world.
5. Move toward the left Menu door. Confirm the action appears only nearby; E, action button and target tap open Menu. Return and verify the character remains in place and stopped.
6. Switch to another app while holding a movement key, then return; verify no continued movement. Repeat with the joystick and cancel/release.
7. On Android, verify portrait display, joystick drag/release/cancel, backgrounding and door navigation independently. Record the tested device/emulator and screenshots.

This change connects the bedroom scene only. Task JSON application-data-path wiring, Dashboard real callbacks and the final end-to-end restart demo remain separate integration work. Finance stays in memory as labelled.

## Visual acceptance correction (2026-10-30)

The first full-sprite collision correction removed furniture overlap but added
an unnatural head-height gap at the bed. The current correction separates three
shapes: the sprite rectangle for rendering, a shallow ground footprint for
furniture collision, and a wider clearance rectangle whose four corners must
remain in the convex floor envelope. Both initial positions and every
movement substep use these checks. This keeps people off the walls while letting
them stand naturally in front of the bed; upper-body overlap with the footboard
is expected perspective, not walking through the furniture. Furniture bounds
and all three shapes remain in the unique SceneGeometry world configuration.

The HUD uses a dark/gold panel at sceneRect's top-left fixed logical margin,
now capped at 128 logical pixels rather than spreading across the scene top.
It remains unscaled and scrollable for large text or tiny viewports. Data remains
explicitly labelled demonstration data. Native visual acceptance is pending.

The floor envelope now extends to y=780 beside the bed, ending below the
bedside cabinet. Furniture still excludes the bed from that envelope. A new
regression walks from spawn up this aisle, then attempts to move into the bed.
HUD text/padding/progress spacing were reduced with the 128-pixel width cap.

## Platform controls and wall following

Desktop hides the mobile joystick and centers the keyboard hint/door action
under the scene. Android/iOS retain the touch joystick in a bounded strip under
the scene. Platform visibility has a Windows widget regression; Android native
placement still requires device acceptance.

Vertical input within two world pixels of a sloping floor edge projects onto
that edge's tangent. W and S follow the same perspective wall line in opposite
directions without moving through it. Projected speed never exceeds requested
speed. Away from contact the original world axes are unchanged; geometry and
input/pointer conversions are not warped. All projected substeps still pass
floor clearance and furniture occupancy checks.
