import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/devices/presentation/screens/devices_screen.dart';
import '../../features/profiles/presentation/providers/profile_provider.dart';
import '../../features/profiles/presentation/screens/profile_picker_screen.dart';
import '../../providers/auth_provider.dart';
import '../../providers/downloads_provider.dart';
import '../../providers/user_prefs_provider.dart';
import '../../screens/downloads_screen.dart';
import '../../screens/login_screen.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dialog_buttons.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_nav_bar.dart' show TvSection;
import '../widgets/tv_sidebar.dart';
import 'tv_search_screen.dart';

/// TV Settings — everything More/Settings has on phone, condensed onto one
/// non-scrolling screen behind the same persistent left sidebar every other
/// TV page has (see TvSidebar). Deliberately a separate screen from the
/// phone MoreScreen rather than that screen reused with kIsTv tweaks: phone
/// Settings is a long vertical list because phone has room to scroll and
/// nothing else competing for the screen, but a remote-driven 10-foot
/// screen has neither — everything here is arranged as a grid of compact
/// tiles instead so it's all reachable and visible at once.
///
/// Deliberately no `PopScope` here — see TvSearchScreen's identical doc
/// comment for the full reasoning (default-pop-back is correct for every
/// pushed screen; only the true root intercepts Back at all).
class TvSettingsScreen extends StatelessWidget {
  final ValueChanged<TvSection> onSelectSection;

  const TvSettingsScreen({super.key, required this.onSelectSection});

  void _selectSidebarItem(BuildContext context, TvSidebarItem item) {
    switch (item) {
      case TvSidebarItem.movies:
        onSelectSection(TvSection.movies);
      case TvSidebarItem.series:
        onSelectSection(TvSection.series);
      case TvSidebarItem.live:
        onSelectSection(TvSection.live);
      case TvSidebarItem.settings:
        break;
      case TvSidebarItem.search:
        pushTv(
          context,
          TvSearchScreen(
            onSelectSection: (s) {
              Navigator.of(context).pop();
              onSelectSection(s);
            },
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.backgroundGradient,
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TvMetrics.sidebarCollapsedWidth,
                    16,
                    40,
                    16,
                  ),
                  child: const _SettingsContent(),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: TvSidebar(
                  active: null,
                  currentItem: TvSidebarItem.settings,
                  isArabic: isArabic,
                  onSelect: (item) => _selectSidebarItem(context, item),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent();

  String _themeModeLabel(ThemeMode mode, bool isArabic) {
    switch (mode) {
      case ThemeMode.system:
        return isArabic ? 'النظام' : 'System';
      case ThemeMode.light:
        return isArabic ? 'فاتح' : 'Light';
      case ThemeMode.dark:
        return isArabic ? 'داكن' : 'Dark';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final userPrefs = context.watch<UserPrefsProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final profileProvider = context.watch<ProfileProvider>();
    final isArabic = userPrefs.locale == 'ar';
    final downloadsCount =
        downloads.completedDownloads.length + downloads.downloading.length;

    String daysLeftText;
    if (user?.expiryDate != null) {
      final diff = user!.expiryDate!.difference(DateTime.now()).inDays;
      if (diff < 0) {
        daysLeftText = isArabic ? 'منتهي' : 'Expired';
      } else if (diff == 0) {
        daysLeftText = isArabic ? 'آخر يوم' : 'Last day';
      } else {
        daysLeftText = isArabic ? '$diff يوم' : '$diff days';
      }
    } else {
      daysLeftText = isArabic ? 'غير محدود' : 'Unlimited';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'الإعدادات' : 'SETTINGS',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            color: colors.ink,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        _InfoStrip(
          colors: colors,
          isArabic: isArabic,
          username: user?.username.toUpperCase() ?? 'GUEST',
          daysLeftText: daysLeftText,
          profileName: profileProvider.activeProfile?.name,
          connections:
              '${user?.activeConnections ?? 0}/${user?.maxConnections ?? 1}',
        ),
        const SizedBox(height: 14),
        Expanded(
          child: GridView.count(
            crossAxisCount: 4,
            childAspectRatio: 2.6,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _SettingsTile(
                icon: Icons.person_rounded,
                label: isArabic ? 'الملف الشخصي' : 'Profile',
                value:
                    profileProvider.activeProfile?.name ??
                    (isArabic ? 'اختر' : 'Choose'),
                autofocus: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfilePickerScreen(isEmbedded: true),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.download_rounded,
                label: isArabic ? 'التنزيلات' : 'Downloads',
                value: '$downloadsCount',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.language_rounded,
                label: isArabic ? 'اللغة' : 'Language',
                value: isArabic ? 'العربية' : 'English',
                onTap: () => _showLanguagePicker(context, userPrefs),
              ),
              _SettingsTile(
                icon: Icons.dark_mode_rounded,
                label: isArabic ? 'المظهر' : 'Theme',
                value: _themeModeLabel(userPrefs.themeMode, isArabic),
                onTap: () => _showThemePicker(context, userPrefs, isArabic),
              ),
              _SettingsTile(
                icon: Icons.play_circle_filled_rounded,
                label: isArabic ? 'تشغيل تلقائي' : 'Auto-play Next',
                value: userPrefs.autoPlayNextEpisode
                    ? (isArabic ? 'ON' : 'ON')
                    : (isArabic ? 'OFF' : 'OFF'),
                active: userPrefs.autoPlayNextEpisode,
                onTap: () => userPrefs.setAutoPlayNextEpisode(
                  !userPrefs.autoPlayNextEpisode,
                ),
              ),
              _SettingsTile(
                icon: auth.isBackendConnected
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                label: isArabic ? 'حالة المزامنة' : 'Sync Status',
                value: auth.isBackendConnected
                    ? (isArabic ? 'متصل' : 'Connected')
                    : (isArabic ? 'غير متصل' : 'Offline'),
                active: auth.isBackendConnected,
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.devices_rounded,
                label: isArabic ? 'الأجهزة' : 'Devices',
                value: '',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DevicesScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.support_agent_rounded,
                label: isArabic ? 'الدعم' : 'Support',
                value: '',
                onTap: () async {
                  final url = Uri.parse('https://wa.me/96550507254');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.logout_rounded,
                label: isArabic ? 'تسجيل الخروج' : 'Log Out',
                value: '',
                onTap: () async {
                  await auth.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.delete_forever_rounded,
                label: isArabic ? 'حذف الحساب' : 'Delete Account',
                value: '',
                danger: true,
                onTap: () => _showDeleteAccountDialog(context, auth, isArabic),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDeleteAccountDialog(
    BuildContext context,
    AuthProvider auth,
    bool isArabic,
  ) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.error, width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.error),
            const SizedBox(width: 10),
            Text(
              isArabic ? 'حذف الحساب؟' : 'Delete Account?',
              style: GoogleFonts.outfit(
                color: colors.ink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          isArabic
              ? 'سيتم حذف هذا الحساب نهائياً مع كل السجل والمفضلة المرتبطة به. لا يمكن التراجع عن هذا الإجراء.'
              : 'This will permanently delete this account along with all its associated history and favorites. This action cannot be undone.',
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7)),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          DialogSecondaryButton(
            label: isArabic ? 'إلغاء' : 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          DialogPrimaryButton(
            label: isArabic ? 'حذف' : 'Delete',
            color: colors.error,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await auth.logout(deleteFromList: true);
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, UserPrefsProvider userPrefs) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          userPrefs.locale == 'ar' ? 'اختر اللغة' : 'Select Language',
          style: GoogleFonts.outfit(
            color: colors.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
        children: [
          _dialogOption(ctx, colors, 'English', userPrefs.locale == 'en', () {
            userPrefs.setLocale('en');
            Navigator.pop(ctx);
          }),
          _dialogOption(ctx, colors, 'العربية', userPrefs.locale == 'ar', () {
            userPrefs.setLocale('ar');
            Navigator.pop(ctx);
          }),
        ],
      ),
    );
  }

  void _showThemePicker(
    BuildContext context,
    UserPrefsProvider userPrefs,
    bool isArabic,
  ) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isArabic ? 'اختر المظهر' : 'Select Theme',
          style: GoogleFonts.outfit(
            color: colors.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
        children: [
          _dialogOption(
            ctx,
            colors,
            _themeModeLabel(ThemeMode.system, isArabic),
            userPrefs.themeMode == ThemeMode.system,
            () {
              userPrefs.setThemeMode(ThemeMode.system);
              Navigator.pop(ctx);
            },
          ),
          _dialogOption(
            ctx,
            colors,
            _themeModeLabel(ThemeMode.light, isArabic),
            userPrefs.themeMode == ThemeMode.light,
            () {
              userPrefs.setThemeMode(ThemeMode.light);
              Navigator.pop(ctx);
            },
          ),
          _dialogOption(
            ctx,
            colors,
            _themeModeLabel(ThemeMode.dark, isArabic),
            userPrefs.themeMode == ThemeMode.dark,
            () {
              userPrefs.setThemeMode(ThemeMode.dark);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Widget _dialogOption(
    BuildContext context,
    AppColors colors,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return TvFocusScope(
      onTap: onTap,
      autofocus: selected,
      builder: (context, focused) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: focused ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused ? colors.brandAccent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: selected ? colors.brandAccent : colors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, color: colors.brandAccent, size: 18),
            ],
          ),
        );
      },
    );
  }
}

/// Single-row strip of small stats — account/profile info that's worth
/// showing but isn't itself an action, so it sits above the tile grid
/// rather than taking one of its slots.
class _InfoStrip extends StatelessWidget {
  final AppColors colors;
  final bool isArabic;
  final String username;
  final String daysLeftText;
  final String? profileName;
  final String connections;

  const _InfoStrip({
    required this.colors,
    required this.isArabic,
    required this.username,
    required this.daysLeftText,
    required this.profileName,
    required this.connections,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      (isArabic ? 'المستخدم' : 'User', username),
      (isArabic ? 'الملف الشخصي' : 'Profile', profileName ?? '—'),
      (isArabic ? 'الأيام المتبقية' : 'Days Left', daysLeftText),
      (isArabic ? 'الأجهزة' : 'Devices', connections),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          for (final (i, (label, value)) in items.indexed) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: colors.ink.withValues(alpha: 0.45),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ),
            if (i != items.length - 1)
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: colors.border,
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final bool danger;
  final bool autofocus;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.value,
    this.active = false,
    this.danger = false,
    this.autofocus = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TvFocusScope(
      autofocus: autofocus,
      onTap: onTap,
      builder: (context, focused) {
        final accentColor = danger ? colors.error : colors.brandAccent;
        return AnimatedContainer(
          duration: TvMetrics.focusAnim,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: focused
                ? accentColor.withValues(alpha: 0.16)
                : colors.surface.withValues(alpha: 0.7),
            border: Border.all(
              color: focused
                  ? accentColor
                  : (danger
                        ? colors.error.withValues(alpha: 0.3)
                        : colors.border),
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: danger
                    ? colors.error
                    : (active
                          ? colors.brandAccent
                          : colors.ink.withValues(alpha: 0.75)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: danger ? colors.error : colors.ink,
                      ),
                    ),
                    if (value.isNotEmpty)
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: colors.ink.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
