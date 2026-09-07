import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../../theme/app_type.dart';
import '../../../../widgets/tv_focusable.dart';
import '../../domain/entities/profile_entity.dart';

/// Fixed palette of avatar colors to choose from when creating/editing a
/// profile. No image assets involved — this app has no bundled avatar
/// artwork (assets/images/ doesn't exist), so each avatar is just the
/// profile's initial on a colored circle, which needs no new binary assets
/// at all and still gives each profile a distinct, recognizable look.
const List<String> kAvatarColorKeys = [
  'purple',
  'blue',
  'cyan',
  'pink',
  'orange',
  'green',
  'red',
  'teal',
];

Color avatarColorForKey(String key, AppColors colors) {
  switch (key) {
    case 'purple':
      return const Color(0xFF7B2A8C);
    case 'blue':
      return const Color(0xFF2547D6);
    case 'cyan':
      return const Color(0xFF12A6DA);
    case 'pink':
      return const Color(0xFFE0479E);
    case 'orange':
      return const Color(0xFFE08A2A);
    case 'green':
      return const Color(0xFF2AA65C);
    case 'red':
      return const Color(0xFFD64545);
    case 'teal':
      return const Color(0xFF12EEE0);
    default:
      return colors.brandPrimary;
  }
}

/// One profile card in the "Who's Watching" grid, and also reused (smaller)
/// in the avatar-color picker on the create/edit screen.
class ProfileAvatarTile extends StatelessWidget {
  final ProfileEntity? profile;
  final String? previewAvatarKey;
  final String? previewName;
  final double size;
  final bool selected;
  final bool showLabel;
  final VoidCallback? onTap;

  const ProfileAvatarTile({
    super.key,
    this.profile,
    this.previewAvatarKey,
    this.previewName,
    this.size = 88,
    this.selected = false,
    this.showLabel = true,
    this.onTap,
  }) : assert(profile != null || previewAvatarKey != null);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final avatarKey = profile?.avatar ?? previewAvatarKey!;
    final name = profile?.name ?? previewName ?? '';
    final color = avatarColorForKey(avatarKey, colors);
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A rounded square, not a circle. Netflix, Prime and Shahid all use
          // one on this screen; a circular avatar reads as a social app, and
          // this is the screen users benchmark the app against hardest.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: color,
              border: Border.all(
                color: selected ? colors.ink : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: colors.brandPrimary.withValues(alpha: 0.40),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: AppType.hero(Colors.white).copyWith(
                fontSize: size * 0.38,
              ),
            ),
          ),
          if (showLabel && name.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: size + 16,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.cardTitle(
                  colors.ink.withValues(alpha: 0.8),
                ).copyWith(fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
