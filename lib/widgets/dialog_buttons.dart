// Real-looking action buttons for AlertDialog's `actions` row.
//
// A bare TextButton sitting in an AlertDialog's actions row renders as
// unbounded colored text with no visible edge — it reads as inert/broken
// rather than as something tappable. These give every dialog action a
// filled or outlined pill so it looks like the button it is.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';

/// The highlighted action in a dialog — e.g. "Delete", "Select Episodes...",
/// "OK". Pass [color] to override the default brand fill (e.g.
/// `colors.error` for a destructive action).
class DialogPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  const DialogPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? colors.brandPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: AppType.sans(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }
}

/// The secondary/dismissive action in a dialog — e.g. "Cancel". Pairs with
/// [DialogPrimaryButton].
class DialogSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const DialogSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink.withValues(alpha: 0.7),
        side: BorderSide(color: colors.ink.withValues(alpha: 0.24)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: AppType.sans(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}
