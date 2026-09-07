import 'package:flutter/material.dart';

/// Centralized semantic color tokens.
///
/// One brand hue, two stops. The five-stop purple-blue-cyan ramp this
/// replaced was the app's clearest generic-template tell; no premium
/// streaming service uses a multi-hue gradient as brand furniture.
///
/// `ink` intentionally replaces the old scattered `Colors.white*` usage as a
/// single base color — callers keep their original opacity via
/// `ink.withValues(alpha: ...)` instead of the palette needing a separate
/// named token per emphasis level.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final List<Color> backgroundGradient;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color border;
  final Color ink;
  final Color brandPrimary;
  final Color brandAccent;
  final List<Color> brandGradient;
  final Color error;

  const AppColors({
    required this.background,
    required this.backgroundGradient,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.border,
    required this.ink,
    required this.brandPrimary,
    required this.brandAccent,
    required this.brandGradient,
    required this.error,
  });

  /// Phone palette. Near-black with a violet bias, three surfaces above it.
  ///
  /// Pure black is deliberately *not* used here — it belongs to the player, so
  /// that entering playback reads as a drop to true black rather than more of
  /// the same surface.
  static const AppColors dark = AppColors(
    background: Color(0xFF08060C),
    backgroundGradient: [
      Color(0xFF120D1A),
      Color(0xFF0A0810),
      Color(0xFF08060C),
    ],
    surface: Color(0xFF110D19),
    surfaceElevated: Color(0xFF171122),
    surfaceMuted: Color(0xFF0C0912),
    border: Color(0xFF241C33),
    ink: Color(0xFFF3EFF8),
    brandPrimary: Color(0xFF9B3BAF),
    // Reserved for the live-broadcast signal only — the on-air dot, the EPG
    // elapsed bar. Never a surface, never a second decorative accent.
    brandAccent: Color(0xFF12EEE0),
    brandGradient: [Color(0xFF6E2280), Color(0xFF9B3BAF)],
    error: Color(0xFFE5484D),
  );

  /// The ten-foot palette — Android TV, iPad, macOS, Windows.
  ///
  /// Kept as its own constant rather than shared with [dark] so retouching the
  /// TV app can never move the phone app. Slightly cooler and one step darker:
  /// living-room screens are larger, dimmer-lit and gain contrast at distance.
  static const AppColors tv = AppColors(
    background: Color(0xFF060509),
    backgroundGradient: [
      Color(0xFF100C18),
      Color(0xFF08070D),
      Color(0xFF060509),
    ],
    surface: Color(0xFF0F0B16),
    surfaceElevated: Color(0xFF16101F),
    surfaceMuted: Color(0xFF0A080F),
    border: Color(0xFF221A30),
    ink: Color(0xFFF3EFF8),
    brandPrimary: Color(0xFF9B3BAF),
    brandAccent: Color(0xFF12EEE0),
    brandGradient: [Color(0xFF6E2280), Color(0xFF9B3BAF)],
    error: Color(0xFFE5484D),
  );

  static const AppColors light = AppColors(
    background: Color(0xFFFAF8FC),
    backgroundGradient: [
      Color(0xFFF4F0F8),
      Color(0xFFFAF8FC),
      Color(0xFFFFFFFF),
    ],
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF4F0F8),
    surfaceMuted: Color(0xFFEDE7F3),
    border: Color(0xFFE3DCEC),
    ink: Color(0xFF16111F),
    brandPrimary: Color(0xFF7E2C92),
    brandAccent: Color(0xFF0BA69B),
    brandGradient: [Color(0xFF5E1D6E), Color(0xFF7E2C92)],
    error: Color(0xFFD03B40),
  );

  @override
  AppColors copyWith({
    Color? background,
    List<Color>? backgroundGradient,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceMuted,
    Color? border,
    Color? ink,
    Color? brandPrimary,
    Color? brandAccent,
    List<Color>? brandGradient,
    Color? error,
  }) {
    return AppColors(
      background: background ?? this.background,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      ink: ink ?? this.ink,
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandAccent: brandAccent ?? this.brandAccent,
      brandGradient: brandGradient ?? this.brandGradient,
      error: error ?? this.error,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      backgroundGradient: [
        for (var i = 0; i < backgroundGradient.length; i++)
          Color.lerp(backgroundGradient[i], other.backgroundGradient[i], t)!,
      ],
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t)!,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!,
      brandGradient: [
        for (var i = 0; i < brandGradient.length; i++)
          Color.lerp(brandGradient[i], other.brandGradient[i], t)!,
      ],
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  /// Shorthand for the active theme's semantic color tokens.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
