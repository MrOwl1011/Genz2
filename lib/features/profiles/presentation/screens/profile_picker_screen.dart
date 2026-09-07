import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../providers/user_prefs_provider.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_type.dart';
import '../../../../widgets/tv_focusable.dart';
import '../../domain/entities/profile_entity.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_avatar_tile.dart';
import 'profile_edit_screen.dart';

/// The "Who's Watching?" screen. Serves two purposes, switched via
/// [isEmbedded]:
///
/// - Root usage (`isEmbedded: false`, the default) — sits in main.dart's
///   AppRoot between a successful Xtream login and
///   MainNavigationScreen, same insertion point/pattern LoginScreen/
///   PlaylistsScreen already use there. Purely reactive: selecting a profile
///   just calls ProfileProvider.selectProfile() and AppRoot (which
///   watches ProfileProvider.hasActiveProfile) swaps to MainNavigationScreen
///   on its own — this screen never navigates anywhere itself in this mode.
///   Shows a logout icon (there's nothing to "go back" to before login).
///
/// - Embedded usage (`isEmbedded: true`) — pushed from More → Viewer Profile
///   so a user can switch/add/edit/delete profiles without logging out.
///   Shows a close icon instead, and pops itself after a successful switch
///   (the reactive AppRoot swap doesn't apply here since this is a
///   pushed route sitting on top of the already-active MainNavigationScreen,
///   not the root content itself).
class ProfilePickerScreen extends StatefulWidget {
  final bool isEmbedded;

  const ProfilePickerScreen({super.key, this.isEmbedded = false});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  bool _manageMode = false;

  void _tapProfile(ProfileEntity profile) {
    if (_manageMode) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileEditScreen(existingProfile: profile),
        ),
      );
      return;
    }
    context.read<ProfileProvider>().selectProfile(profile);
    if (widget.isEmbedded) {
      Navigator.of(context).pop();
    }
  }

  void _addProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileEditScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final provider = context.watch<ProfileProvider>();
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.backgroundGradient,
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        widget.isEmbedded
                            ? Icons.close_rounded
                            : Icons.logout_rounded,
                        color: colors.ink.withValues(alpha: 0.5),
                      ),
                      tooltip: widget.isEmbedded
                          ? (isArabic ? 'إغلاق' : 'Close')
                          : (isArabic ? 'تسجيل الخروج' : 'Log out'),
                      onPressed: widget.isEmbedded
                          ? () => Navigator.of(context).pop()
                          : () => context.read<AuthProvider>().logout(),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                isArabic ? 'من يشاهد؟' : "Who's Watching?",
                style: AppType.sans(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: colors.ink,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 40),
              if (provider.isLoading && provider.profiles.isEmpty)
                CircularProgressIndicator(color: colors.brandPrimary)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final p in provider.profiles)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ProfileAvatarTile(
                              profile: p,
                              onTap: () => _tapProfile(p),
                            ),
                            if (_manageMode)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: colors.brandAccent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.edit_rounded,
                                    color: Colors.black,
                                    size: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      if (provider.canCreateMore)
                        _buildAddTile(colors, isArabic),
                    ],
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _manageMode = !_manageMode),
                child: Text(
                  _manageMode
                      ? (isArabic ? 'تم' : 'Done')
                      : (isArabic
                            ? 'إدارة الملفات الشخصية'
                            : 'Manage Profiles'),
                  style: AppType.sans(
                    color: colors.ink.withValues(alpha: 0.6),
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddTile(AppColors colors, bool isArabic) {
    return TvFocusable(
      onTap: _addProfile,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surface,
              border: Border.all(color: colors.border, width: 1.5),
            ),
            child: Icon(
              Icons.add_rounded,
              color: colors.ink.withValues(alpha: 0.5),
              size: 36,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isArabic ? 'إضافة ملف شخصي' : 'Add Profile',
            style: AppType.sans(
              color: colors.ink.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
