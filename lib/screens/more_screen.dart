import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/user_prefs_provider.dart';
import 'login_screen.dart';
import 'playlists_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;
    final userPrefs = Provider.of<UserPrefsProvider>(context);
    final isArabic = userPrefs.locale == 'ar';

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
              // Screen Title
              Text(
                isArabic ? 'المزيد' : 'MORE',
                style: GoogleFonts.outfit(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),

              // Profile Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF2A0508),
                    width: 1.5,
                  ),
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
                            style: GoogleFonts.outfit(
                              color: Colors.white,
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
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              user?.status.toUpperCase() ?? 'ACTIVE',
                              style: GoogleFonts.outfit(
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

              // Account Details Info Panel
              _buildSectionHeader(
                isArabic ? 'تفاصيل الاشتراك' : 'Subscription Details',
              ),
              const SizedBox(height: 12),
              _buildInfoContainer([
                _buildInfoRow(
                  isArabic ? 'الأيام المتبقية' : 'Days Left',
                  daysLeftText,
                ),
                _buildInfoRow(
                  isArabic ? 'الأجهزة المتصلة' : 'Online Devices',
                  '${user?.activeConnections ?? 0}',
                ),
                _buildInfoRow(
                  isArabic ? 'الأجهزة المسموحة' : 'Allowed devices',
                  '${user?.maxConnections ?? 1}',
                ),
              ]),

              const SizedBox(height: 24),

              // Supported Streams Info
              _buildSectionHeader(
                isArabic ? 'توافق النظام' : 'System Compatibility',
              ),
              const SizedBox(height: 12),
              _buildInfoContainer([
                _buildInfoRow(
                  isArabic ? 'إصدار المحرك' : 'Engine Version',
                  'v1.4.2-NX',
                ),
                _buildInfoRow(
                  isArabic ? 'بدون إعلانات' : 'Ad-Free Mode',
                  isArabic ? 'مفعل (مدى الحياة)' : 'Enabled (Lifetime)',
                ),
              ]),

              const SizedBox(height: 24),

              // Help & Support
              _buildSectionHeader(isArabic ? 'المساعدة والدعم' : 'Help & Support'),
              const SizedBox(height: 12),
              GestureDetector(
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
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white10,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.support_agent_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isArabic ? 'تواصل معنا عبر الواتساب' : 'CONTACT US ON WHATSAPP',
                          style: GoogleFonts.outfit(
                            color: Colors.white70,
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

              // Settings Section
              _buildSectionHeader(isArabic ? 'الإعدادات' : 'Settings'),
              const SizedBox(height: 12),
              _buildInfoContainer([
                _buildActionRow(
                  context,
                  icon: Icons.language_rounded,
                  label: isArabic ? 'اللغة' : 'Language',
                  value: currentLanguageLabel,
                  onTap: () => _showLanguagePicker(context, userPrefs),
                ),
                _buildSwitchRow(
                  context,
                  icon: Icons.play_circle_filled_rounded,
                  label: isArabic ? 'تشغيل الحلقة التالية تلقائياً' : 'Auto Play Next Episode',
                  value: userPrefs.autoPlayNextEpisode,
                  onChanged: (val) => userPrefs.setAutoPlayNextEpisode(val),
                ),
              ]),

              const SizedBox(height: 36),

              // Logout Button
              GestureDetector(
                onTap: () async {
                  await auth.logout(deleteFromList: true);
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
                    color: const Color(0xFF1F0305),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: const Color(0xFF881014),
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
                          style: GoogleFonts.outfit(
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
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, UserPrefsProvider userPrefs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                userPrefs.locale == 'ar' ? 'اختر اللغة' : 'Select Language',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
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
    final isSelected = userPrefs.locale == localeCode;
    return ListTile(
      title: Text(
        label,
        style: GoogleFonts.outfit(
          color: isSelected ? Theme.of(context).primaryColor : Colors.white,
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildInfoContainer(List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A0508), width: 1),
      ),
      child: Column(
        children: List.generate(children.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Divider(
              color: const Color(0xFF2A0508).withValues(alpha: 0.5),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white60,
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
              style: GoogleFonts.outfit(
                color: Colors.white,
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
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white38,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow(
    BuildContext context, {
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
              style: GoogleFonts.outfit(
                color: Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: primaryColor,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }
}
