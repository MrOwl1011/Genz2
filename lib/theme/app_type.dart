import 'package:flutter/widgets.dart';

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

  /// The bundled Latin family. Declared in pubspec under this exact name.
  static const String family = 'Archivo';

  /// The bundled Arabic family.
  static const String arabicFamily = 'IBMPlexSansArabic';

  /// Builds a style on the bundled variable font.
  ///
  /// Sets `fontVariations` as well as `fontWeight`. Archivo ships as a single
  /// variable file whose default weight is 600, and `fontWeight` alone does
  /// not reliably drive the `wght` axis across every platform Flutter
  /// targets — without the explicit variation, regular text renders
  /// semibold on some of them.
  static TextStyle sans({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color? color,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    List<Shadow>? shadows,
    double? wdth,
  }) {
    return TextStyle(
      fontFamily: family,
      // Archivo has no Arabic glyphs, so without this every Arabic string
      // fell through to whatever the platform supplies — a different face
      // with different metrics, which is why Arabic screens never quite
      // lined up with their English counterparts.
      //
      // A fallback rather than switching family by locale, because this app
      // mixes scripts inside single strings ("S5 E8 - الامتداد S05 E08" in
      // one label). Per-locale switching renders half of that in the wrong
      // face; a fallback resolves it glyph by glyph.
      fontFamilyFallback: const <String>[arabicFamily],
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontVariations: <FontVariation>[
        FontVariation('wght', fontWeight.value.toDouble()),
        if (wdth != null) FontVariation('wdth', wdth),
      ],
      height: height,
      letterSpacing: letterSpacing,
      color: color,
      fontStyle: fontStyle,
      decoration: decoration,
      shadows: shadows,
    );
  }

  /// Hero titles: detail pages, the home backdrop.
  static TextStyle hero(Color color) => sans(
    fontSize: 32,
    height: 1.06,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.96,
    color: color,
  );

  /// The ten-foot variant of [hero] — read at distance, so it grows rather
  /// than simply scaling with the layout.
  static TextStyle heroTv(Color color) => sans(
    fontSize: 44,
    height: 1.04,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.32,
    color: color,
  );

  /// Between [hero] and [heading] — the largest thing on a screen that is
  /// not the screen's subject.
  static TextStyle display(Color color) => sans(
    fontSize: 24,
    height: 1.14,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.48,
    color: color,
  );

  /// Screen headings and section titles.
  static TextStyle heading(Color color) => sans(
    fontSize: 22,
    height: 1.18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.44,
    color: color,
  );

  /// Sub-headings inside a screen — a card's own heading, a dialog title.
  static TextStyle title(Color color) => sans(
    fontSize: 18,
    height: 1.22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.18,
    color: color,
  );

  /// Content-row headers ("Continue Watching", "Action").
  static TextStyle rowHeader(Color color) => sans(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: color,
  );

  /// Titles on cards, list rows and episode rows.
  static TextStyle cardTitle(Color color) => sans(
    fontSize: 14,
    height: 1.28,
    fontWeight: FontWeight.w600,
    color: color,
  );

  /// Synopsis and any running prose.
  static TextStyle body(Color color) => sans(
    fontSize: 14,
    height: 1.57,
    fontWeight: FontWeight.w400,
    color: color,
  );

  /// Secondary prose — the line under a title, a row's supporting text.
  static TextStyle bodySmall(Color color) => sans(
    fontSize: 13,
    height: 1.46,
    fontWeight: FontWeight.w500,
    color: color,
  );

  /// Captions beneath posters. Two lines maximum, by convention.
  static TextStyle caption(Color color) => sans(
    fontSize: 12,
    height: 1.33,
    fontWeight: FontWeight.w500,
    color: color,
  );

  /// The smallest readable step — dense TV rows, badge text.
  static TextStyle captionSmall(Color color) => sans(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: color,
  );

  /// Year, duration, rating, quality — and every uppercase label.
  ///
  /// The wide tracking is not decorative: at this size it is what keeps
  /// uppercase legible, and it is the visual counterweight to the tight
  /// tracking on [hero].
  static TextStyle meta(Color color) => sans(
    fontSize: 10.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.47,
    color: color,
  );

  /// Button and action labels.
  static TextStyle label(Color color) => sans(
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.14,
    color: color,
  );

  /// Forces a style entirely into IBM Plex Sans Arabic.
  ///
  /// Rarely needed: [sans] already lists the Arabic family as a fallback, so
  /// Arabic glyphs resolve to it automatically, script by script, even inside
  /// a mixed string. Use this only where a whole block must be set in the
  /// Arabic face regardless of what characters it happens to contain.
  static TextStyle arabic(TextStyle base) => base.copyWith(
    fontFamily: arabicFamily,
    // Plex Arabic ships as static weights, so the variable-axis instruction
    // meant for Archivo has to be cleared or it is applied to a font that
    // has no such axis.
    fontVariations: const <FontVariation>[],
  );
}
