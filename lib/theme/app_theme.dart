import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.dark.background,
    primaryColor: AppColors.dark.brandPrimary,
    colorScheme: ColorScheme.dark(
      primary: AppColors.dark.brandPrimary,
      secondary: AppColors.dark.brandAccent,
      surface: AppColors.dark.surface,
      error: AppColors.dark.error,
    ),
    extensions: const [AppColors.dark],
  );

  static final ThemeData light = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.light.background,
    primaryColor: AppColors.light.brandPrimary,
    colorScheme: ColorScheme.light(
      primary: AppColors.light.brandPrimary,
      secondary: AppColors.light.brandAccent,
      surface: AppColors.light.surface,
      error: AppColors.light.error,
    ),
    extensions: const [AppColors.light],
  );
}
