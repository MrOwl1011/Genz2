import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';

/// The "Cast" tab: labelled text blocks for whatever Xtream actually
/// provides. There's no per-actor endpoint (no photos, no individual
/// filmographies) — cast/director are single free-text fields from the
/// panel, so a real cast grid would mean fabricating structure the data
/// doesn't have. This shows exactly what's there, laid out for legibility
/// rather than pretending it's richer than it is.
class TvCastInfo extends StatelessWidget {
  final String cast;
  final String director;
  final String genre;
  final bool isArabic;

  const TvCastInfo({
    super.key,
    required this.cast,
    required this.director,
    required this.genre,
    required this.isArabic,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = <(String, String)>[
      if (cast.isNotEmpty) (isArabic ? 'الطاقم' : 'Cast', cast),
      if (director.isNotEmpty) (isArabic ? 'الإخراج' : 'Director', director),
      if (genre.isNotEmpty) (isArabic ? 'النوع' : 'Genre', genre),
    ];

    if (entries.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا توجد معلومات.' : 'No cast information available.',
          style: AppType.body(colors.ink.withValues(alpha: 0.4)),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        final (label, value) = entries[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: AppType.sans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppType.sans(
                fontSize: 13,
                height: 1.4,
                color: colors.ink.withValues(alpha: 0.85),
              ),
            ),
          ],
        );
      },
    );
  }
}
