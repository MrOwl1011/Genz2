import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import 'tv_focus.dart';

/// The tab row on the right-hand column of a detail screen (Episodes / More
/// Like This / Cast). A plain state-holding row rather than Flutter's
/// TabBar/TabController: those drive their indicator off a
/// PageView/TabBarView's scroll position, which has no meaning here — only
/// one tab's content is ever mounted at a time, each backed by its own
/// (possibly async) fetch, so there is no shared scroll axis to synchronize
/// an indicator to in the first place.
class TvDetailTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  const TvDetailTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          TvFocusScope(
            onTap: () => onSelect(i),
            builder: (context, focused) {
              final isSelected = i == selected;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labels[i],
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: isSelected
                          ? colors.brandAccent
                          : (focused
                                ? colors.ink
                                : colors.ink.withValues(alpha: 0.5)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 2,
                    width: isSelected ? 28 : (focused ? 16 : 0),
                    color: isSelected
                        ? colors.brandAccent
                        : colors.ink.withValues(alpha: 0.6),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 26),
        ],
      ],
    );
  }
}
