// Resume playback dialog widget.
// Shows a styled dialog asking the user to resume from last position
// or start over. Used when saved position is greater than 30 seconds.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Shows a resume dialog and returns `true` to resume, `false` to start over,
/// or `null` if dismissed (treated as resume by default).
Future<bool?> showResumeDialog(BuildContext context, int positionSeconds) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => _ResumeDialog(positionSeconds: positionSeconds),
  );
}

class _ResumeDialog extends StatelessWidget {
  final int positionSeconds;
  const _ResumeDialog({required this.positionSeconds});

  /// Formats seconds into a human-readable string like "1h 23m 45s".
  String _formatTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: colors.brandPrimary.withValues(alpha: 0.15),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.brandPrimary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_circle_outline_rounded,
                  color: colors.brandPrimary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Resume Playback?',
                style: GoogleFonts.outfit(
                  color: colors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle with formatted time
              Text(
                'You stopped at ${_formatTime(positionSeconds)}',
                style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.54), fontSize: 14),
              ),
              const SizedBox(height: 24),

              // Resume button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  label: Text(
                    'Resume',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.brandPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Start Over button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(
                    Icons.replay_rounded,
                    color: colors.ink.withValues(alpha: 0.6),
                    size: 20,
                  ),
                  label: Text(
                    'Start Over',
                    style: GoogleFonts.outfit(
                      color: colors.ink.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.ink.withValues(alpha: 0.24)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
