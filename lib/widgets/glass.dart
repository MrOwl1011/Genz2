import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The three blur tiers, and the only sanctioned way to draw one.
///
/// ## Glass is structure, not texture
///
/// A blurred panel over a flat background is a gradient with extra GPU cost,
/// and it reads as ornament immediately. Glass belongs only where a surface
/// genuinely floats above moving content — chrome over artwork, or over video.
///
/// ## The cost, which matters most on the weakest hardware
///
/// [BackdropFilter] forces a `saveLayer` and re-rasterises everything beneath
/// it every frame. Android TV boxes are the least capable devices this app
/// ships to, and they are also where the sidebar, the EPG panel and the player
/// chrome all want to be glass at once.
///
/// **Never more than two live blurs on screen.** Anything that scrolls —
/// poster cards, list tiles, EPG rows — uses a solid `surfaceElevated` fill
/// instead. Glass is for fixed chrome. Check any screen that adds one with
/// `flutter run --profile` and watch the raster thread, not the UI thread.
enum GlassTier {
  /// Player controls and hero fades. Darkens rather than lightens, and takes
  /// no border: an edge would draw a box around content that should feel
  /// continuous with the video beneath it.
  scrim,

  /// Navigation bars, app bars, the TV sidebar, filter rails.
  chrome,

  /// Modal sheets, dialogs, the EPG detail card.
  sheet,
}

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.tier,
    required this.child,
    this.radius = BorderRadius.zero,
    this.padding = EdgeInsets.zero,
  });

  final GlassTier tier;
  final Widget child;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;

  double get _sigma => switch (tier) {
    GlassTier.scrim => 8,
    GlassTier.chrome => 18,
    GlassTier.sheet => 32,
  };

  Color get _fill => switch (tier) {
    GlassTier.scrim => const Color(0x61000000), // black 38%
    GlassTier.chrome => const Color(0x0FFFFFFF), // white 6%
    GlassTier.sheet => const Color(0x17FFFFFF), // white 9%
  };

  /// Opacity of the brightest point of the hairline, or null for no edge.
  double? get _edge => switch (tier) {
    GlassTier.scrim => null,
    GlassTier.chrome => 0.14,
    GlassTier.sheet => 0.18,
  };

  @override
  Widget build(BuildContext context) {
    final edge = _edge;

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(color: _fill, borderRadius: radius),
      child: child,
    );

    // A single-colour hairline reads as a stroke drawn around a box. A
    // gradient one reads as an edge catching light, which is the whole
    // difference between glass and a translucent rectangle. Flutter's
    // Border takes no gradient, so the edge is painted as a 1px gradient
    // underlay with the fill inset on top of it.
    if (edge != null) {
      content = Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: edge),
              Colors.white.withValues(alpha: edge / 3.5),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Container(
            padding: padding,
            color: _fill,
            child: child,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma),
        child: content,
      ),
    );
  }
}
