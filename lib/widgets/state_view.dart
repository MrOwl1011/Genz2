import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_type.dart';

/// The shared anatomy for every empty and error state in the app.
///
/// One thin-stroke icon, one line of heading, one line of explanation, and at
/// most one action. Deliberately no illustration: a bespoke empty-state
/// drawing is the fastest way to look like a template, and no premium
/// streaming service uses one.
///
/// Error copy names the cause *and* the fix — "Your provider did not respond.
/// Check the server address in Settings." Never "Something went wrong", which
/// tells the user nothing they could act on.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.isError = false,
    this.autofocusAction = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  /// Ten-foot screens must autofocus the action, or a remote arrives on a
  /// screen with nowhere to go.
  final bool autofocusAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = isError ? colors.error : colors.ink;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: accent.withValues(alpha: 0.2)),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppType.rowHeader(colors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppType.body(colors.ink.withValues(alpha: 0.55)),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              TextButton(
                autofocus: autofocusAction,
                onPressed: onAction,
                style: TextButton.styleFrom(
                  backgroundColor: colors.ink,
                  foregroundColor: colors.background,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: AppType.label(colors.background),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
