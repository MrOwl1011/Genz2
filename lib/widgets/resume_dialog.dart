// Resume playback dialog widget.
// Shows a styled dialog asking the user to resume from last position
// or start over. Used when saved position is greater than 30 seconds.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';

/// Shows a resume dialog and returns `true` to resume, `false` to start over,
/// or `null` if dismissed via the X button or tapping outside — callers must
/// treat `null` as "cancelled, don't open the player at all", not as resume.
///
/// [episodeLabel], when the item being resumed is a series episode (e.g.
/// "Season 1 · Episode 3"), is shown above the stopped-at time so it's clear
/// which episode is being continued — movies pass nothing and the line is
/// simply omitted.
Future<bool?> showResumeDialog(
  BuildContext context,
  int positionSeconds, {
  String? episodeLabel,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => _ResumeDialog(
      positionSeconds: positionSeconds,
      episodeLabel: episodeLabel,
    ),
  );
}

class _ResumeDialog extends StatelessWidget {
  final int positionSeconds;
  final String? episodeLabel;
  const _ResumeDialog({required this.positionSeconds, this.episodeLabel});

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
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';
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
        child: Stack(
          children: [
            Padding(
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
                    isArabic ? 'استئناف التشغيل؟' : 'Resume Playback?',
                    style: GoogleFonts.archivo(
                      color: colors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (episodeLabel != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      episodeLabel!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.archivo(
                        color: colors.brandPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),

                  // Subtitle with formatted time
                  Text(
                    isArabic
                        ? 'توقفت عند ${_formatTime(positionSeconds)}'
                        : 'You stopped at ${_formatTime(positionSeconds)}',
                    style: GoogleFonts.archivo(
                      color: colors.ink.withValues(alpha: 0.54),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Resume button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      // Resume is the default action, so it takes focus as
                      // soon as the dialog opens: on a remote that means
                      // OK/Select resumes straight away instead of landing
                      // on nothing and making the user hunt for a button.
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      label: Text(
                        isArabic ? 'استئناف' : 'Resume',
                        style: GoogleFonts.archivo(
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
                        isArabic ? 'البدء من جديد' : 'Start Over',
                        style: GoogleFonts.archivo(
                          color: colors.ink.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: colors.ink.withValues(alpha: 0.24),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Close button — same effect as tapping the barrier (dismiss,
            // returns null, treated by callers as "cancelled" per
            // showResumeDialog's contract).
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: colors.ink.withValues(alpha: 0.54),
                ),
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
