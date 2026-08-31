import 'package:flutter/material.dart';

/// Centralized semantic color tokens for the app's purple/blue/cyan brand.
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

  static const AppColors dark = AppColors(
    background: Color(0xFF0B0713),
    backgroundGradient: [
      Color(0xFF2A0E4A),
      Color(0xFF0B0713),
      Color(0xFF000000),
    ],
    surface: Color(0xFF170C22),
    surfaceElevated: Color(0xFF1A1A1A),
    surfaceMuted: Color(0xFF1E1E1E),
    border: Color(0xFF2E1640),
    ink: Colors.white,
    brandPrimary: Color(0xFF7B2A8C),
    brandAccent: Color(0xFF12EEE0),
    brandGradient: [
      Color(0xFF2A0E4A),
      Color(0xFF7B2A8C),
      Color(0xFF2547D6),
      Color(0xFF12A6DA),
      Color(0xFF12EEE0),
    ],
    error: Color(0xFFE5484D),
  );

  /// The TV app's own dark palette — deliberately separate from [dark]
  /// rather than a shared constant, so retouching the TV app's colors can
  /// never accidentally change the phone app's look (which keeps using
  /// [dark]/[light] exactly as before). Neutral near-black with purple used
  /// only as an accent (selection, focus, progress), not as the dominant
  /// surface colour — see main_tv.dart for where this gets wired in.
  static const AppColors tv = AppColors(
    background: Color(0xFF0B0B0F),
    backgroundGradient: [
      Color(0xFF15111F),
      Color(0xFF0D0D12),
      Color(0xFF0B0B0F),
    ],
    surface: Color(0xFF18181F),
    surfaceElevated: Color(0xFF1E1E27),
    surfaceMuted: Color(0xFF101014),
    border: Color(0xFF27272A),
    ink: Colors.white,
    brandPrimary: Color(0xFF7C3AED),
    brandAccent: Color(0xFF8B5CF6),
    brandGradient: [Color(0xFF5B21B6), Color(0xFF7C3AED), Color(0xFF8B5CF6)],
    error: Color(0xFFE5484D),
  );

  static const AppColors light = AppColors(
    background: Color(0xFFF7F5FA),
    backgroundGradient: [
      Color(0xFFF3EEFA),
      Color(0xFFF7F5FA),
      Color(0xFFFFFFFF),
    ],
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF1ECFB),
    surfaceMuted: Color(0xFFECE7F2),
    border: Color(0xFFE1D9EC),
    ink: Color(0xFF1A1523),
    brandPrimary: Color(0xFF7B2A8C),
    brandAccent: Color(0xFF12EEE0),
    brandGradient: [
      Color(0xFF2A0E4A),
      Color(0xFF7B2A8C),
      Color(0xFF2547D6),
      Color(0xFF12A6DA),
      Color(0xFF12EEE0),
    ],
    error: Color(0xFFE5484D),
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
