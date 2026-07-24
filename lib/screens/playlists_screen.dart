import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/playlist_model.dart';
import '../providers/auth_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';
import 'playlist_history_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<Playlist> _playlists = [];
  Map<String, int> _historyCounts = {};
  final Set<String> _revealedPasswordIds = {};
  bool _isLoading = true;

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    if (mounted) setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userPrefs = Provider.of<UserPrefsProvider>(context, listen: false);

    final playlists = await auth.getSavedPlaylistModels();
    final counts = <String, int>{};
    await Future.wait(
      playlists.map((p) async {
        counts[p.id] = await userPrefs.getHistoryCountForPlaylist(p.id);
      }),
    );

    if (mounted) {
      setState(() {
        _playlists = playlists;
        _historyCounts = counts;
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime? date, bool isArabic) {
    if (date == null) return isArabic ? 'أبداً' : 'Never';
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  void _onPlaylistLogin(Playlist playlist) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final colors = context.colors;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: colors.brandPrimary),
      ),
    );

    final success = await auth.login(
      playlist.playlistName,
      playlist.serverUrl,
      playlist.username,
      playlist.password,
    );

    if (mounted) {
      Navigator.of(context).pop(); // dismiss loading dialog

      if (success) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colors.error,
            content: Text(
              auth.errorMessage ?? 'Failed to connect to playlist',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  void _onPlaylistEdit(Playlist playlist) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LoginScreen(editPlaylist: playlist.toMap()),
          ),
        )
        .then((_) => _loadPlaylists());
  }

  void _onPlaylistHistory(Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistHistoryScreen(playlist: playlist),
      ),
    );
  }

  void _onPlaylistDelete(Playlist playlist) {
    final userPrefs = Provider.of<UserPrefsProvider>(context, listen: false);
    final isArabic = userPrefs.locale == 'ar';
    final name = playlist.playlistName;
    final colors = context.colors;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          isArabic ? 'حذف القائمة؟' : 'Delete Playlist?',
          style: GoogleFonts.outfit(color: colors.ink),
        ),
        content: Text(
          isArabic
              ? 'هل أنت متأكد من حذف "$name"؟\nسيتم حذف كل السجل والمفضلة المرتبطة بها.'
              : 'Are you sure you want to delete "$name"?\nThis will remove all associated history and favorites.',
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(color: colors.ink),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _doDeletePlaylist(playlist);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.outfit(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _doDeletePlaylist(Playlist playlist) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    bool wasActive =
        (auth.serverUrl == playlist.serverUrl &&
        auth.username == playlist.username);

    await auth.deletePlaylist(playlist.serverUrl, playlist.username);

    if (!mounted) return;

    if (wasActive) {
      await auth.logout(); // This clears the active status safely
      final playlists = await auth.getSavedPlaylists();
      if (mounted) {
        if (playlists.isEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        } else {
          _loadPlaylists();
        }
      }
    } else {
      _loadPlaylists();
    }
  }

  void _onAddNewTap() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(isAddingNew: true),
          ),
        )
        .then((_) => _loadPlaylists());
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final userPrefs = Provider.of<UserPrefsProvider>(context);
    final isArabic = userPrefs.locale == 'ar';
    final colors = context.colors;

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // App Bar Area
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: colors.ink,
                      ),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        }
                      },
                    ),
                    Expanded(
                      child: Text(
                        isArabic ? 'القوائم المحفوظة' : 'SAVED PLAYLISTS',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: colors.ink,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // balance back button
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (_isLoading)
                Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: colors.brandPrimary),
                  ),
                )
              else if (_playlists.isEmpty)
                Expanded(child: _buildEmptyState(isArabic))
              else
                Expanded(child: _buildResponsiveList(isArabic)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isArabic) {
    final colors = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.playlist_add_check_circle_outlined,
            color: colors.ink.withValues(alpha: 0.24),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            isArabic ? 'لا توجد قوائم محفوظة بعد' : 'No saved playlists yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.54), fontSize: 15),
          ),
          const SizedBox(height: 24),
          _buildAddNewCard(isArabic),
        ],
      ),
    );
  }

  Widget _buildResponsiveList(bool isArabic) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1000 ? 3 : (width >= 600 ? 2 : 1);

        final items = <Widget>[
          ..._playlists.map((p) => _buildPlaylistCard(p, isArabic)),
          _buildAddNewCard(isArabic),
        ];

        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += crossAxisCount) {
          final rowItems = items.skip(i).take(crossAxisCount).toList();
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int j = 0; j < crossAxisCount; j++) ...[
                    if (j > 0) const SizedBox(width: 16),
                    Expanded(
                      child: j < rowItems.length
                          ? rowItems[j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          physics: const BouncingScrollPhysics(),
          children: rows,
        );
      },
    );
  }

  Widget _buildPlaylistCard(Playlist playlist, bool isArabic) {
    final colors = context.colors;
    final isRevealed = _revealedPasswordIds.contains(playlist.id);
    final historyCount = _historyCounts[playlist.id] ?? 0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 12),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
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
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    playlist.playlistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: colors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _infoRow(
              Icons.dns_outlined,
              isArabic ? 'الخادم' : 'Server',
              playlist.serverUrl,
            ),
            const SizedBox(height: 8),
            _infoRow(
              Icons.person_outline_rounded,
              isArabic ? 'المستخدم' : 'Username',
              playlist.username,
            ),
            const SizedBox(height: 8),
            _infoRow(
              Icons.lock_outline_rounded,
              isArabic ? 'كلمة المرور' : 'Password',
              isRevealed ? playlist.password : playlist.maskedPassword,
              trailing: IconButton(
                icon: Icon(
                  isRevealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: colors.ink.withValues(alpha: 0.38),
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    if (isRevealed) {
                      _revealedPasswordIds.remove(playlist.id);
                    } else {
                      _revealedPasswordIds.add(playlist.id);
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            _infoRow(
              Icons.event_available_rounded,
              isArabic ? 'آخر تسجيل دخول' : 'Last Login',
              _formatDate(playlist.lastLogin, isArabic),
            ),
            const SizedBox(height: 8),
            _infoRow(
              Icons.history_rounded,
              isArabic ? 'السجل' : 'History',
              isArabic ? '$historyCount عنصر' : '$historyCount items',
            ),
            const SizedBox(height: 14),
            Divider(color: colors.border, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _actionButton(
                  icon: Icons.play_circle_fill_rounded,
                  color: colors.brandPrimary,
                  tooltip: isArabic ? 'تسجيل الدخول' : 'Login',
                  onTap: () => _onPlaylistLogin(playlist),
                ),
                _actionButton(
                  icon: Icons.edit_rounded,
                  color: colors.ink.withValues(alpha: 0.7),
                  tooltip: isArabic ? 'تعديل' : 'Edit',
                  onTap: () => _onPlaylistEdit(playlist),
                ),
                _actionButton(
                  icon: Icons.history_rounded,
                  color: colors.ink.withValues(alpha: 0.7),
                  tooltip: isArabic ? 'عرض السجل' : 'View History',
                  onTap: () => _onPlaylistHistory(playlist),
                ),
                _actionButton(
                  icon: Icons.delete_outline_rounded,
                  color: colors.error,
                  tooltip: isArabic ? 'حذف' : 'Delete',
                  onTap: () => _onPlaylistDelete(playlist),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Widget? trailing,
  }) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: colors.ink.withValues(alpha: 0.38), size: 15),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.outfit(
            color: colors.ink.withValues(alpha: 0.38),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: colors.ink.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildAddNewCard(bool isArabic) {
    final colors = context.colors;
    return GestureDetector(
      onTap: _onAddNewTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: colors.surfaceElevated.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.ink.withValues(alpha: 0.24), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.brandPrimary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isArabic ? 'إضافة قائمة جديدة' : 'Add New Playlist',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: colors.ink,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
