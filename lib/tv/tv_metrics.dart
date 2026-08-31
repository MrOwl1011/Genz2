import 'package:flutter/widgets.dart';

/// Shared layout constants for the TV ("10-foot") interface.
class TvMetrics {
  TvMetrics._();

  /// TVs overscan: many sets physically crop the outer edge of the panel, or
  /// apply their own zoom, so Google's TV guidelines reserve roughly 5% of
  /// each edge as a dead zone. Every TV screen lays its content out inside
  /// this margin so nothing important can be cut off.
  static const EdgeInsets safeArea = EdgeInsets.symmetric(
    horizontal: 40,
    vertical: 20,
  );

  /// Gap between tiles/pills in the home hub grid.
  static const double gap = 16;

  /// How much a focused element grows. Deliberately modest — the colour
  /// change carries most of the signal, and a large scale on a wide tile
  /// visibly overlaps its neighbours.
  static const double focusScale = 1.06;

  static const Duration focusAnim = Duration(milliseconds: 150);

  static const double tileRadius = 20;
  static const double pillRadius = 14;

  // ─── Row-based home layout ─────────────────────────────────────────────

  /// Height of the old persistent top navigation bar. No longer used by
  /// TvHomeScreen/TvLiveScreen (replaced by the left TvSidebar below), kept
  /// only in case another screen still references it.
  static const double navHeight = 44;

  /// Width of the persistent left navigation rail (TvSidebar) in its
  /// icon-only resting state. Content columns (TvHomeScreen, TvLiveScreen)
  /// reserve exactly this much fixed left inset for it — the sidebar is a
  /// pure overlay above that: expanding never changes the content layout,
  /// it just draws further over the first ~150px of it, so there's no
  /// layout jank while the user is navigating in and out of it.
  static const double sidebarCollapsedWidth = 76;

  /// Width the sidebar animates to while focus is anywhere inside it, wide
  /// enough for every label without truncation.
  static const double sidebarExpandedWidth = 220;

  /// Sidebar expand/collapse duration — subtle and fast per the design
  /// brief (150–250ms), matching [focusAnim]'s per-item highlight speed so
  /// the whole rail reads as one smooth motion rather than two competing
  /// animation speeds.
  static const Duration sidebarAnim = Duration(milliseconds: 200);

  /// Fraction of the viewport the featured hero occupies.
  static const double heroHeightFactor = 0.44;

  static const double posterAspect = 2 / 3;

  /// Near-square corners, matching the reference design's tight poster
  /// frames rather than the app's usual pill-like rounding.
  static const double posterRadius = 4;

  /// Gap between posters within a row, and between rows.
  static const double posterGap = 10;
  static const double rowGap = 20;

  /// How many slots a content row aims to fit across the screen — 8 media
  /// posters plus the See All tile as the 9th, so the button is always
  /// visible on screen rather than needing a scroll to reach.
  ///
  /// Keep in sync with the row's own item cap (see tv_content_row.dart):
  /// this is that cap plus one for the tile.
  static const int postersPerRow = 9;

  /// Width of one poster, derived from the screen rather than fixed.
  ///
  /// A constant can't work here: a 1080p TV reports ~960 logical pixels wide
  /// (1920 physical at 2.0 density), while a 4K panel or a differently
  /// configured box reports something else entirely — so any hardcoded width
  /// is only ever correct on one device, and was landing at nearly a fifth of
  /// the screen per poster on the emulator. Deriving it from the actual
  /// viewport keeps the row's *proportions* stable everywhere, which is what
  /// the design is really specified in.
  static double posterWidth(double screenWidth) {
    final usable = screenWidth - safeArea.horizontal;
    return (usable - posterGap * (postersPerRow - 1)) / postersPerRow;
  }

  /// Full height of a content row: artwork plus the title/subtitle beneath
  /// it, plus slack so a focus-scaled card isn't clipped by the row bounds.
  static double rowHeight(double screenWidth) =>
      posterWidth(screenWidth) / posterAspect + 56;
}
