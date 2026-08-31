import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../providers/user_prefs_provider.dart';
import '../../../../theme/app_colors.dart';
import '../../../../widgets/sync_pairing_dialogs.dart';
import '../../../../widgets/tv_focusable.dart';
import '../../../devices/data/datasources/device_remote_datasource.dart';
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

  // Sync status chip — null while still loading/unknown, so the chip stays
  // hidden rather than flashing a wrong "not synced" state for a moment on
  // every open. See _loadDeviceCount.
  int? _deviceCount;

  // The deviceToken this screen has already fetched a count for (or
  // attempted to) — a plain one-shot fetch in initState missed the token
  // entirely on a fresh login: AuthProvider's backend registration is
  // deliberately fire-and-forget (see _connectBackendAndProfiles's doc
  // comment) and this screen typically appears before that network round
  // trip finishes, so deviceToken was still null the one time this used to
  // check it — and, having checked once, never checked again. Tracking
  // what's already been fetched-for and re-running whenever build() sees a
  // *new* token (including null → non-null, the common case right after
  // login) fixes that without ever double-fetching for the same token.
  String? _fetchedForToken;

  void _maybeLoadDeviceCount(String? token) {
    if (token == null || token == _fetchedForToken) return;
    _fetchedForToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeviceCount(token));
  }

  /// Forces a re-check even if the token hasn't changed — used right after
  /// joining/pairing, where "show my code" doesn't get a new token at all
  /// but the account's device count just changed regardless.
  void _refreshDeviceCount() {
    final token = context.read<AuthProvider>().deviceToken;
    if (token == null) return;
    _fetchedForToken = null;
    _maybeLoadDeviceCount(token);
  }

  Future<void> _loadDeviceCount(String token) async {
    try {
      final devices = await DeviceRemoteDataSource().list(token);
      if (!mounted) return;
      setState(() => _deviceCount = devices.length);
    } catch (_) {
      // Non-fatal — the chip just stays hidden, same as "not connected".
      // _fetchedForToken stays set so a transient failure doesn't retry on
      // every rebuild; logging back in (a genuinely new token) still does.
    }
  }

  // Join-only, deliberately — this screen (Who's Watching) is reached
  // before/without necessarily being the device someone wants to treat as
  // the "source of truth" to show a code from; generating/showing a code
  // to pull *other* devices onto this one is still available from Settings
  // (see more_screen.dart), which is the intentional place for that. This
  // used to offer both as a chooser dialog; now there's only one action,
  // so it goes straight to entering a code instead of a dialog with a
  // single option in it.
  void _showSyncOptions(BuildContext context, bool isArabic) {
    final authProvider = context.read<AuthProvider>();
    showJoinCodeDialog(context, authProvider: authProvider, isArabic: isArabic)
        .then((_) => _refreshDeviceCount());
  }

  Widget _buildSyncChip(AppColors colors, bool isArabic) {
    final count = _deviceCount;
    if (count == null) return const SizedBox.shrink();
    final isSynced = count > 1;

    return TvFocusable(
      onTap: () => _showSyncOptions(context, isArabic),
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: (isSynced ? Colors.green : colors.ink).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: (isSynced ? Colors.green : colors.ink).withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSynced ? Icons.check_circle_rounded : Icons.sync_rounded,
              size: 15,
              color: isSynced ? Colors.green : colors.ink.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              isSynced
                  ? (isArabic ? 'متزامن' : 'Synced')
                  : (isArabic ? 'مزامنة' : 'Sync'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSynced ? Colors.green : colors.ink.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
    // Reactive, not one-shot: deviceToken is very often still null on this
    // screen's first frame (see _maybeLoadDeviceCount's doc comment), so
    // this needs to keep checking on every rebuild until it sees a real
    // token, not just once in initState.
    _maybeLoadDeviceCount(context.watch<AuthProvider>().deviceToken);

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
                    _buildSyncChip(colors, isArabic),
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
                style: GoogleFonts.outfit(
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
                  style: GoogleFonts.outfit(
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
            style: GoogleFonts.outfit(
              color: colors.ink.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
