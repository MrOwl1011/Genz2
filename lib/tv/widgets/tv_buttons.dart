import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../tv_metrics.dart';
import 'tv_focus.dart';

/// A large primary destination tile for the TV home hub — the Live / Movies /
/// Series / Favorites row.
///
/// Focused, it fills with the brand gradient, turns its icon and label white
/// and picks up an accent glow; unfocused it sits back as a dark translucent
/// card with an accent-coloured icon. That inversion (rather than a subtle
/// outline) is what makes the selected tile readable from across a room,
/// which is the whole job of a focus state on TV.
class TvDestinationTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  const TvDestinationTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TvFocusScope(
      onTap: onTap,
      autofocus: autofocus,
      builder: (context, focused) {
        return AnimatedScale(
          scale: focused ? TvMetrics.focusScale : 1,
          duration: TvMetrics.focusAnim,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: TvMetrics.focusAnim,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TvMetrics.tileRadius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: focused
                    ? colors.brandGradient
                    : [
                        colors.surface.withValues(alpha: 0.75),
                        colors.surface.withValues(alpha: 0.35),
                      ],
              ),
              border: Border.all(
                color: focused ? colors.ink : colors.border,
                width: focused ? 2.5 : 1.5,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: colors.brandPrimary.withValues(alpha: 0.45),
                        blurRadius: 28,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: Icon(
                      icon,
                      size: 68,
                      color: focused ? Colors.white : colors.ink,
                    ),
                  ),
                ),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 1,
                    color: focused ? Colors.white : colors.ink,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A secondary action pill for the row beneath the destination tiles —
/// Refresh / Account / Settings / Downloads. Same focus language as
/// [TvDestinationTile], at a smaller scale so the visual hierarchy between
/// "where you're going" and "what you're doing" stays obvious.
class TvActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const TvActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TvFocusScope(
      onTap: onTap,
      builder: (context, focused) {
        return AnimatedScale(
          scale: focused ? TvMetrics.focusScale : 1,
          duration: TvMetrics.focusAnim,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: TvMetrics.focusAnim,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TvMetrics.pillRadius),
              gradient: focused
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors.brandGradient,
                    )
                  : null,
              color: focused ? null : colors.surface.withValues(alpha: 0.6),
              border: Border.all(
                color: focused ? colors.ink : colors.border,
                width: focused ? 2.5 : 1.5,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: colors.brandPrimary.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: focused ? Colors.white : colors.ink,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: focused
                          ? Colors.white
                          : colors.ink.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
