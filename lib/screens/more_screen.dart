import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/build_flavor.dart' show kIsTv;
import '../providers/auth_provider.dart';
import '../providers/downloads_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import '../features/profiles/presentation/providers/profile_provider.dart';
import '../features/profiles/presentation/screens/profile_picker_screen.dart';
import '../features/profiles/presentation/widgets/profile_avatar_tile.dart';
import 'downloads_screen.dart';
import 'login_screen.dart';
import '../widgets/dialog_buttons.dart';
import '../widgets/tv_focusable.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static String _themeModeLabel(ThemeMode mode, bool isArabic) {
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
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;
    final userPrefs = Provider.of<UserPrefsProvider>(context);
    final downloads = Provider.of<DownloadsProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final isArabic = userPrefs.locale == 'ar';
    final colors = context.colors;
    final downloadsCount =
        downloads.completedDownloads.length + downloads.downloading.length;

    // Calculate days left
    String daysLeftText;
    if (user?.expiryDate != null) {
      final now = DateTime.now();
      final diff = user!.expiryDate!.difference(now).inDays;
      if (diff < 0) {
        daysLeftText = isArabic ? 'منتهي' : 'Expired';
      } else if (diff == 0) {
        daysLeftText = isArabic ? 'آخر يوم' : 'Last Day';
      } else {
        daysLeftText = isArabic ? '$diff يوم' : '$diff days';
      }
    } else {
      daysLeftText = isArabic
          ? 'مدى الحياة / غير محدود'
          : 'Lifetime / Unlimited';
    }

    final currentLanguageLabel = isArabic ? 'العربية' : 'English';
    final currentThemeLabel = _themeModeLabel(userPrefs.themeMode, isArabic);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: 100,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen Title — on TV this is pushed as its own route (see
              // TvHomeScreen._pushSection), unlike phone where it's a
              // permanent bottom-nav tab, so it needs a way back that a
              // tab body never does.
              Row(
                children: [
                  if (kIsTv)
                    TvFocusable(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: colors.ink,
                          size: 26,
                        ),
                      ),
                    ),
                  Text(
                    isArabic ? 'المزيد' : 'MORE',
                    style: AppType.sans(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: colors.ink,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Profile Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.border, width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.username.toUpperCase() ?? 'NX GUEST',
                            style: AppType.sans(
                              color: colors.ink,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).primaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).primaryColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              user?.status.toUpperCase() ?? 'ACTIVE',
                              style: AppType.sans(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Viewer Profile — Netflix-style profiles (separate from the
              // Xtream account card above).
              _buildSectionHeader(
                isArabic ? 'الملف الشخصي' : 'Viewer Profile',
                colors,
              ),
              const SizedBox(height: 12),
              TvFocusable(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfilePickerScreen(isEmbedded: true),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.border, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      if (profileProvider.activeProfile != null)
                        ProfileAvatarTile(
                          profile: profileProvider.activeProfile,
                          size: 44,
                          showLabel: false,
                        )
                      else
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.brandPrimary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            color: colors.brandPrimary,
                            size: 22,
                          ),
                        ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profileProvider.activeProfile?.name ??
                                  (isArabic
                                      ? 'اختر ملفاً شخصياً'
                                      : 'Select a profile'),
                              style: AppType.sans(
                                color: colors.ink,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isArabic
                                  ? 'إدارة أو تبديل الملفات الشخصية'
                                  : 'Switch, add, edit or delete profiles',
                              style: AppType.sans(
                                color: colors.ink.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.ink.withValues(alpha: 0.38),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Account Details Info Panel
              _buildSectionHeader(
                isArabic ? 'تفاصيل الاشتراك' : 'Subscription Details',
                colors,
              ),
              const SizedBox(height: 12),
              _buildInfoContainer(colors, [
                _buildInfoRow(
                  colors,
                  isArabic ? 'الأيام المتبقية' : 'Days Left',
                  daysLeftText,
                ),
                _buildInfoRow(
                  colors,
                  isArabic ? 'الأجهزة المتصلة' : 'Online Devices',
                  '${user?.activeConnections ?? 0}',
                ),
                _buildInfoRow(
                  colors,
                  isArabic ? 'الأجهزة المسموحة' : 'Allowed devices',
                  '${user?.maxConnections ?? 1}',
                ),
              ]),

              const SizedBox(height: 24),

              // Help & Support
              _buildSectionHeader(
                isArabic ? 'المساعدة والدعم' : 'Help & Support',
                colors,
              ),
              const SizedBox(height: 12),
              TvFocusable(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final url = Uri.parse('https://wa.me/96550507254');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.ink.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colors.ink.withValues(alpha: 0.1),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.support_agent_rounded,
                          color: colors.ink.withValues(alpha: 0.7),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isArabic
                              ? 'تواصل معنا عبر الواتساب'
                              : 'CONTACT US ON WHATSAPP',
                          style: AppType.sans(
                            color: colors.ink.withValues(alpha: 0.7),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Sync diagnostics — see AuthProvider.backendError for why
              // this is on screen rather than only in debugPrint.
              _buildSectionHeader(isArabic ? 'المزامنة' : 'Sync', colors),
              const SizedBox(height: 12),
              _buildInfoContainer(colors, [
                Builder(
                  builder: (context) {
                    final auth = context.watch<AuthProvider>();
                    final ok = auth.isBackendConnected;
                    final err = auth.backendError;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            ok
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_off_rounded,
                            color: ok ? colors.brandPrimary : colors.error,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ok
                                      ? (isArabic ? 'متصل' : 'Connected')
                                      : (isArabic
                                            ? 'غير متصل'
                                            : 'Not connected'),
                                  style: AppType.sans(
                                    color: colors.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (!ok) ...[
                                  const SizedBox(height: 4),
                                  // The raw reason, verbatim. Deliberately
                                  // not prettified into a friendly message:
                                  // this exists to be reported back when a
                                  // specific device won't sync.
                                  Text(
                                    err ?? 'No error recorded yet.',
                                    style: AppType.sans(
                                      color: colors.ink.withValues(alpha: 0.6),
                                      fontSize: 11.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Divider(
                  color: colors.ink.withValues(alpha: 0.08),
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                ),
              ]),
              const SizedBox(height: 24),

              // Settings Section
              _buildSectionHeader(isArabic ? 'الإعدادات' : 'Settings', colors),
              const SizedBox(height: 12),
              _buildInfoContainer(colors, [
                _buildActionRow(
                  context,
                  colors,
                  icon: Icons.download_rounded,
                  label: isArabic ? 'التنزيلات' : 'Downloads',
                  value: '$downloadsCount',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                  ),
                ),
                _buildActionRow(
                  context,
                  colors,
                  icon: Icons.language_rounded,
                  label: isArabic ? 'اللغة' : 'Language',
                  value: currentLanguageLabel,
                  onTap: () => _showLanguagePicker(context, userPrefs),
                ),
                _buildActionRow(
                  context,
                  colors,
                  icon: Icons.dark_mode_rounded,
                  label: isArabic ? 'المظهر' : 'Theme',
                  value: currentThemeLabel,
                  onTap: () => _showThemePicker(context, userPrefs, isArabic),
                ),
                _buildSwitchRow(
                  context,
                  colors,
                  icon: Icons.play_circle_filled_rounded,
                  label: isArabic
                      ? 'تشغيل الحلقة التالية تلقائياً'
                      : 'Auto Play Next Episode',
                  value: userPrefs.autoPlayNextEpisode,
                  onChanged: (val) => userPrefs.setAutoPlayNextEpisode(val),
                ),
              ]),

              const SizedBox(height: 36),

              // Logout Button
              TvFocusable(
                borderRadius: BorderRadius.circular(6),
                onTap: () async {
                  // Logout only ends the session — the playlist stays saved
                  // so it still appears in "Users" for one-tap re-login.
                  // Deleting it entirely is a separate, explicit action there.
                  await auth.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (route) => false,
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colors.brandPrimary.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isArabic ? 'تسجيل الخروج' : 'LOG OUT ACCOUNT',
                          style: AppType.sans(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Delete Account Button
              TvFocusable(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _showDeleteAccountDialog(context, auth, isArabic),
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colors.error.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.delete_forever_rounded,
                          color: colors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isArabic ? 'حذف الحساب' : 'DELETE ACCOUNT',
                          style: AppType.sans(
                            color: colors.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
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
              style: AppType.sans(
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
          style: AppType.sans(color: colors.ink.withValues(alpha: 0.7)),
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
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: colors.ink.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                userPrefs.locale == 'ar' ? 'اختر اللغة' : 'Select Language',
                style: AppType.sans(
                  color: colors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Divider(color: colors.ink.withValues(alpha: 0.1), height: 1),
            _buildLanguageOption(
              ctx,
              userPrefs,
              label: 'English',
              localeCode: 'en',
            ),
            _buildLanguageOption(
              ctx,
              userPrefs,
              label: 'العربية',
              localeCode: 'ar',
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(
    BuildContext context,
    UserPrefsProvider userPrefs, {
    required String label,
    required String localeCode,
  }) {
    final colors = context.colors;
    final isSelected = userPrefs.locale == localeCode;
    return ListTile(
      title: Text(
        label,
        style: AppType.sans(
          color: isSelected ? Theme.of(context).primaryColor : colors.ink,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: Theme.of(context).primaryColor)
          : null,
      onTap: () {
        userPrefs.setLocale(localeCode);
        Navigator.pop(context);
      },
    );
  }

  void _showThemePicker(
    BuildContext context,
    UserPrefsProvider userPrefs,
    bool isArabic,
  ) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: colors.ink.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                isArabic ? 'اختر المظهر' : 'Select Theme',
                style: AppType.sans(
                  color: colors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Divider(color: colors.ink.withValues(alpha: 0.1), height: 1),
            _buildThemeOption(
              ctx,
              userPrefs,
              mode: ThemeMode.system,
              label: _themeModeLabel(ThemeMode.system, isArabic),
            ),
            _buildThemeOption(
              ctx,
              userPrefs,
              mode: ThemeMode.light,
              label: _themeModeLabel(ThemeMode.light, isArabic),
            ),
            _buildThemeOption(
              ctx,
              userPrefs,
              mode: ThemeMode.dark,
              label: _themeModeLabel(ThemeMode.dark, isArabic),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    UserPrefsProvider userPrefs, {
    required ThemeMode mode,
    required String label,
  }) {
    final colors = context.colors;
    final isSelected = userPrefs.themeMode == mode;
    return ListTile(
      title: Text(
        label,
        style: AppType.sans(
          color: isSelected ? Theme.of(context).primaryColor : colors.ink,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: Theme.of(context).primaryColor)
          : null,
      onTap: () {
        userPrefs.setThemeMode(mode);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildSectionHeader(String title, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Text(
        title.toUpperCase(),
        // Uppercase group labels in the metadata style — the iOS Settings
        // convention every OTT app on the platform follows for inset groups.
        style: AppType.meta(colors.ink.withValues(alpha: 0.5)),
      ),
    );
  }

  Widget _buildInfoContainer(AppColors colors, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        children: List.generate(children.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Divider(
              color: colors.border.withValues(alpha: 0.5),
              height: 1,
              indent: 16,
              endIndent: 16,
            );
          }
          return children[index ~/ 2];
        }),
      ),
    );
  }

  Widget _buildInfoRow(AppColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppType.sans(
              color: colors.ink.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.sans(
                color: colors.ink,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    AppColors colors, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppType.sans(
                color: colors.ink.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: AppType.sans(
                color: colors.ink,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.ink.withValues(alpha: 0.38),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow(
    BuildContext context,
    AppColors colors, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final primaryColor = Theme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.sans(
                color: colors.ink.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: primaryColor,
            inactiveTrackColor: colors.ink.withValues(alpha: 0.12),
            focusColor: colors.brandAccent.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}
