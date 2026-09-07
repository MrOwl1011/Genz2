import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'tv_focus.dart';

/// One circular action button in a detail screen's action row (Play,
/// Favorite, Download, …). Filled white like the phone versions, primary
/// variant uses the brand gradient instead — the visual language the
/// reference design and the rest of this app's brand both already use for
/// "the one button that matters most" on a card.
class TvDetailActionButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool autofocus;
  final double size;

  const TvDetailActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TvFocusScope(
      onTap: onTap,
      autofocus: autofocus,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary ? null : Colors.white,
            gradient: primary
                ? LinearGradient(colors: colors.brandGradient)
                : null,
            border: Border.all(
              color: focused ? colors.ink : Colors.transparent,
              width: 3,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: colors.brandPrimary.withValues(alpha: 0.5),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: icon,
        );
      },
    );
  }
}
