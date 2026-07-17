import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../providers/user_prefs_provider.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<Map<String, String>> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final playlists = await auth.getSavedPlaylists();
    if (mounted) {
      setState(() {
        _playlists = playlists;
        _isLoading = false;
      });
    }
  }

  void _onPlaylistTap(Map<String, String> playlist) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      ),
    );

    final success = await auth.login(
      playlist['name'] ?? 'My Playlist',
      playlist['url'] ?? '',
      playlist['username'] ?? '',
      playlist['password'] ?? '',
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
            backgroundColor: const Color(0xFFE50914),
            content: Text(
              auth.errorMessage ?? 'Failed to connect to playlist',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  void _showManagementMenu(Map<String, String> playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF160103),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  playlist['name'] ?? 'Playlist Options',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.white),
                title: Text('Edit Playlist Name', style: GoogleFonts.outfit(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showEditNameDialog(playlist);
                },
              ),
              ListTile(
                leading: const Icon(Icons.manage_accounts_rounded, color: Colors.white),
                title: Text('Edit Login Details', style: GoogleFonts.outfit(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LoginScreen(editPlaylist: playlist),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Color(0xFFE50914)),
                title: Text('Delete Playlist', style: GoogleFonts.outfit(color: const Color(0xFFE50914))),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(playlist);
                },
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.close_rounded, color: Colors.white54),
                title: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white54)),
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showEditNameDialog(Map<String, String> playlist) {
    final controller = TextEditingController(text: playlist['name']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E0306),
        title: Text('Edit Playlist Name', style: GoogleFonts.outfit(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black45,
            hintText: 'Enter new name',
            hintStyle: GoogleFonts.outfit(color: Colors.white30),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2C0A0D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE50914)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final auth = Provider.of<AuthProvider>(context, listen: false);
                await auth.updatePlaylistName(
                  playlist['url'] ?? '',
                  playlist['username'] ?? '',
                  newName,
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  _loadPlaylists();
                }
              }
            },
            child: Text('Save', style: GoogleFonts.outfit(color: const Color(0xFFE50914), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, String> playlist) {
    final name = playlist['name'] ?? 'My Playlist';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E0306),
        title: Text(
          'Delete Playlist?',
          style: GoogleFonts.outfit(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "$name"?\nThis will remove all associated history and favorites.',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _onDeletePlaylist(playlist);
            },
            child: Text('Delete', style: GoogleFonts.outfit(color: const Color(0xFFE50914))),
          ),
        ],
      ),
    );
  }

  void _onAddNewTap() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen(isAddingNew: true)),
    );
  }

  void _onDeletePlaylist(Map<String, String> playlist) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    
    bool wasActive = (auth.serverUrl == playlist['url'] && auth.username == playlist['username']);
    
    await auth.deletePlaylist(playlist['url'] ?? '', playlist['username'] ?? '');
    
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

  @override
  Widget build(BuildContext context) {
    final userPrefs = Provider.of<UserPrefsProvider>(context);
    final isArabic = userPrefs.locale == 'ar';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF300408),
              Color(0xFF0C0002),
              Color(0xFF030000),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // App Bar Area
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                      onPressed: () {
                        // Check if we can pop (e.g. came from MoreScreen)
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          // Otherwise we just go to login
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
                        }
                      },
                    ),
                    Expanded(
                      child: Text(
                        isArabic ? 'اختر الحساب؟' : 'WHICH PLAYLIST?',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // balance back button
                  ],
                ),
              ),
              const SizedBox(height: 60),

              if (_isLoading)
                const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
              else
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 30,
                      mainAxisSpacing: 40,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: _playlists.length + 1, // +1 for "Add New"
                    itemBuilder: (context, index) {
                      if (index < _playlists.length) {
                        return _buildPlaylistAvatar(_playlists[index]);
                      } else {
                        return _buildAddNewAvatar(isArabic);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistAvatar(Map<String, String> playlist) {
    final name = playlist['name'] ?? 'My Playlist';
    
    return GestureDetector(
      onTap: () => _onPlaylistTap(playlist),
      onLongPress: () => _showManagementMenu(playlist),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFFE50914),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE50914).withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 60,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddNewAvatar(bool isArabic) {
    return GestureDetector(
      onTap: _onAddNewTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white24,
                width: 2,
              ),
            ),
            child: Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFFE50914),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isArabic ? 'إضافة جديد' : 'Add New',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
