import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Every text style in the app, in one place.
///
/// ## Why Archivo
///
/// The app previously set all 258 of its text styles with `GoogleFonts.outfit`.
/// Outfit is a geometric sans with circular bowls and a single optical size:
/// pleasant, and the default of every template. It has no condensed cut for
/// dense channel/EPG rows, no display weight with real presence at a hero size,
/// and no matching Arabic — that fell back to whatever the platform supplied,
/// so an Arabic UI never matched its Latin one.
///
/// Archivo is a grotesque with a genuine editorial history, weights to 800, and
/// proportions that hold up both at 10pt metadata and 48pt hero. It pairs with
/// IBM Plex Sans Arabic, which is drawn to sit *alongside* a Latin grotesque
/// rather than merely beside it — see [arabic].
///
/// ## The one rule
///
/// Hierarchy is carried by weight and tracking, never by colour. Titles are
/// heavy and negatively tracked; metadata is small, uppercase and widely
/// tracked. That contrast is the signature of broadcast UI, and it survives
/// being rendered on a phone at arm's length or a television at three metres.
class AppType {
  AppType._();

  /// Hero titles: detail pages, the home backdrop.
  static TextStyle hero(Color color) => GoogleFonts.archivo(
    fontSize: 32,
    height: 1.06,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.96,
    color: color,
  );

  /// The ten-foot variant of [hero] — read at distance, so it grows rather
  /// than simply scaling with the layout.
  static TextStyle heroTv(Color color) => GoogleFonts.archivo(
    fontSize: 44,
    height: 1.04,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.32,
    color: color,
  );

  /// Screen headings and section titles.
  static TextStyle heading(Color color) => GoogleFonts.archivo(
    fontSize: 22,
    height: 1.18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.44,
    color: color,
  );

  /// Content-row headers ("Continue Watching", "Action").
  static TextStyle rowHeader(Color color) => GoogleFonts.archivo(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: color,
  );

  /// Titles on cards, list rows and episode rows.
  static TextStyle cardTitle(Color color) => GoogleFonts.archivo(
    fontSize: 14,
    height: 1.28,
    fontWeight: FontWeight.w600,
    color: color,
  );

  /// Synopsis and any running prose.
  static TextStyle body(Color color) => GoogleFonts.archivo(
    fontSize: 14,
    height: 1.57,
    fontWeight: FontWeight.w400,
    color: color,
  );

  /// Captions beneath posters. Two lines maximum, by convention.
  static TextStyle caption(Color color) => GoogleFonts.archivo(
    fontSize: 12,
    height: 1.33,
    fontWeight: FontWeight.w500,
    color: color,
  );

  /// Year, duration, rating, quality — and every uppercase label.
  ///
  /// The wide tracking is not decorative: at this size it is what keeps
  /// uppercase legible, and it is the visual counterweight to the tight
  /// tracking on [hero].
  static TextStyle meta(Color color) => GoogleFonts.archivo(
    fontSize: 10.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.47,
    color: color,
  );

  /// Button and action labels.
  static TextStyle label(Color color) => GoogleFonts.archivo(
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.14,
    color: color,
  );

  /// Re-cuts any style above in IBM Plex Sans Arabic.
  ///
  /// Call this for Arabic strings instead of letting the renderer fall back:
  /// a fallback face has different proportions and vertical metrics, so a
  /// mixed screen ends up with rows that do not share a baseline.
  static TextStyle arabic(TextStyle base) =>
      GoogleFonts.ibmPlexSansArabic(textStyle: base);
}
