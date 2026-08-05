# 001 — Polish material hierarchy and media transitions

- **Status**: DONE
- **Commit**: 6c27769
- **Severity**: HIGH
- **Category**: Easing, performance, cohesion, accessibility
- **Estimated scope**: 5 files, app chrome + media presentation feedback + guarded recovery work

## Problem

The app used a default opaque navigation/tab presentation while settings cells
used several independent visual defaults. The Control Center media transition
was installed on the entire module view, so a media swap could move/fade the
module chrome and make a sibling-layout change look like a flying card. The
resize feedback was an opaque black rectangle and the caption appeared/disappeared
without an interruptible transition. The module also allocated an unused
one-second linear blur animator during every controller mount.

## Target

- Use system material navigation/tab appearances with one accent color and no
  hard separator line.
- Keep grouped settings readable with quiet separators and consistent system
  surfaces.
- Animate only media layers during a media swap, using the strong ease-out
  curve `cubic-bezier(0.23, 1, 0.32, 1)` and a 140–420ms bounded duration.
- Use scale `0.94` press feedback for the resize handle and a 140–180ms
  transform/opacity feedback pill.
- Respect `UIAccessibilityIsReduceMotionEnabled()` by removing movement while
  retaining a short opacity response.
- Do not modify playback, selected media, expanded/compact state, grid-size
  persistence, or native-player ownership.

## Repo conventions to follow

- App accent is resolved by `CCBGAppAccentColor()` in
  `app/CCBGControls.m`.
- The Control Center module already owns media layers and uses Core Animation
  for media transitions in `module/CleanCCBG2x2.m`.

## Steps

1. Configure the app-wide material/nav/tab and grouped-table appearance in
   `app/CCBGControls.m` and `app/CCBGMainTabBarController.m`.
2. Add a rounded, bordered material treatment to the media-library header and
   selected media rows in `app/CCBGRootController.m`.
3. Add a short, interruptible preview entrance and clearer status chrome in
   `app/CCBGPreviewController.m`.
4. Style the Control Center resize handle/caption and animate only their
   transform/opacity feedback in `module/CleanCCBG2x2.m`.
5. Scope media transitions to the image/player layers, keep the short material
   prewarm, and preserve all player/layout code paths.
6. Guard native-player recovery layout passes and invalidate stale asynchronous
   preload completions by playback generation.

## Boundaries

- Do not change media catalog keys, module-slot isolation, playback selection,
  native player setup, grid-size calculations, or automation behavior.
- Do not add dependencies or a new animation framework.
- Do not animate width/height/layout during a media transition.

## Verification

- **Mechanical**: run `python scripts/validate_source.py`,
  `python scripts/test_repack_roothide.py`, and `git diff --check`.
- **Feel check**: open the app and scroll settings; confirm the material bars
  stay stable and list scrolling does not stutter. In Control Center switch a
  compact video repeatedly and confirm only the media content transitions.
  Drag the resize handle and confirm it follows the finger, the feedback pill
  appears/disappears smoothly, and the handle remains available afterward.
  Enable reduced motion and confirm the same interactions retain opacity
  feedback without scale movement.
- **Done when**: app chrome is visually cohesive, media swaps no longer move
  the module frame, and existing player/grid behavior is unchanged.
