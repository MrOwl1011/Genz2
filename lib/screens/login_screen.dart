import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import 'playlists_screen.dart';

class LoginScreen extends StatefulWidget {
  final Map<String, String>? editPlaylist;
  final bool isAddingNew;
  const LoginScreen({super.key, this.editPlaylist, this.isAddingNew = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Populate controllers with saved credentials once the provider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);

      if (widget.editPlaylist != null) {
        // We are editing an existing playlist from the switcher
        _nameController.text = widget.editPlaylist!['name'] ?? '';
        _serverController.text = widget.editPlaylist!['url'] ?? '';
        _usernameController.text = widget.editPlaylist!['username'] ?? '';
        _passwordController.text = widget.editPlaylist!['password'] ?? '';
      } else if (!widget.isAddingNew && !auth.isAuthenticated) {
        // We are on the main login screen (not adding from switcher)
        if (auth.playlistName.isNotEmpty && auth.playlistName != 'My Playlist') {
          _nameController.text = auth.playlistName;
        }
        if (auth.serverUrl.isNotEmpty) {
          _serverController.text = auth.serverUrl;
        }
        if (auth.username.isNotEmpty) {
          _usernameController.text = auth.username;
        }
        if (auth.password.isNotEmpty) {
          _passwordController.text = auth.password;
        }
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    // Clear keyboard focus
    FocusScope.of(context).unfocus();

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.login(
      _nameController.text,
      _serverController.text,
      _usernameController.text,
      _passwordController.text,
      oldUrl: widget.editPlaylist?['url'],
      oldUser: widget.editPlaylist?['username'],
    );

    if (mounted) {
      if (success) {
        // Route back through AuthRootHandler rather than straight to
        // MainNavigationScreen — it reactively picks ProfilePickerScreen vs
        // MainNavigationScreen based on ProfileProvider.hasActiveProfile,
        // which right after a login is almost always false (a profile
        // hasn't been chosen yet — see AuthProvider._connectBackendAndProfiles,
        // which deliberately doesn't auto-select one). Jumping straight to
        // MainNavigationScreen skipped the profile picker entirely, and for
        // an account with existing profiles, skipped profile-scoped storage
        // too (UserPrefsProvider never got told which profile to use).
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthRootHandler()),
          (route) => false,
        );
      } else {
        // Show styled error dialog if login fails
        _showErrorDialog(auth.errorMessage ?? 'An unknown error occurred');
      }
    }
  }

  void _showErrorDialog(String message) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.error, width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: colors.error),
            const SizedBox(width: 10),
            Text(
              'Connection Error',
              style: GoogleFonts.outfit(
                color: colors.ink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: GoogleFonts.outfit(
                color: colors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final colors = context.colors;

    // If auto-logged in, navigate automatically — through AuthRootHandler,
    // same reasoning as _handleLogin() above.
    if (auth.isAuthenticated && !auth.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthRootHandler()),
        );
      });
    }

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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Branding
                  Column(
                    children: [
                      // Styled Wide Italic Logo to match "LIVE", "MOVIES" typography
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'GenZ',
                            style: GoogleFonts.outfit(
                              fontSize: 50,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: colors.brandPrimary,
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            '+',
                            style: GoogleFonts.outfit(
                              fontSize: 50,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: colors.ink,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'YOUR ULTIMATE ENTERTAINMENT WORLD',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: colors.ink.withValues(alpha: 0.38),
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),

                  // Login Form
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Playlist Name field intentionally removed from the
                        // UI — Netflix-style profiles (added inside the app)
                        // now cover per-viewer naming, so asking for a
                        // playlist name up front is redundant. _nameController
                        // is still populated (silently) in initState() with
                        // the existing name when editing a saved playlist, or
                        // left empty for a fresh login — AuthProvider.login()
                        // already falls back to "My Playlist" for an empty
                        // name, so this doesn't lose anything, it just stops
                        // asking.

                        // Server URL Input
                        _buildInputField(
                          controller: _serverController,
                          label: 'Server URL',
                          hint: 'http://example.com:8080',
                          icon: Icons.dns_outlined,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Server URL is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Username Input
                        _buildInputField(
                          controller: _usernameController,
                          label: 'Username',
                          hint: 'Enter username',
                          icon: Icons.person_outline_rounded,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Password Input
                        _buildInputField(
                          controller: _passwordController,
                          label: 'Password',
                          hint: 'Enter password',
                          icon: Icons.lock_outline_rounded,
                          isPassword: true,
                          obscureText: _obscurePassword,
                          onTogglePassword: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Password is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildTermsNotice(),
                        const SizedBox(height: 24),

                        // Login Action Button or Loading Indicator
                        auth.isLoading
                            ? Center(
                                child: SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      colors.brandPrimary,
                                    ),
                                    strokeWidth: 3.5,
                                  ),
                                ),
                              )
                            : Container(
                                height: 58,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(30),
                                  gradient: LinearGradient(
                                    colors: colors.brandGradient,
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.brandPrimary.withValues(alpha: 0.4),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  child: Text(
                                    'CONNECT NOW',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Users Button — opens the saved playlists switcher
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
                      );
                    },
                    icon: Icon(Icons.switch_account_rounded, color: colors.ink.withValues(alpha: 0.7), size: 20),
                    label: Text(
                      'Users',
                      style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: colors.ink.withValues(alpha: 0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: colors.ink.withValues(alpha: 0.1)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Contact Us Button
                  TextButton.icon(
                    onPressed: () async {
                      final url = Uri.parse('https://wa.me/96550507254');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: Icon(Icons.support_agent_rounded, color: colors.ink.withValues(alpha: 0.7), size: 20),
                    label: Text(
                      'Contact Us',
                      style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: colors.ink.withValues(alpha: 0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: colors.ink.withValues(alpha: 0.1)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTermsNotice() {
    final colors = context.colors;
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: GoogleFonts.outfit(
          fontSize: 12,
          color: colors.ink.withValues(alpha: 0.54),
        ),
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Terms & Privacy Policy',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colors.brandPrimary,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _showTermsDialog(),
          ),
        ],
      ),
    );
  }

  void _showTermsDialog() {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.border, width: 1.5),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Terms & Privacy Policy',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.ink.withValues(alpha: 0.7)),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              Divider(color: colors.border, height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About GENz+',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colors.brandPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        'GENz+ is a modern IPTV media player designed to provide a smooth, fast, and premium viewing experience. The app supports user-provided playlists, allowing you to organize and enjoy your live TV, movies, and series in one place.',
                      ),
                      const SizedBox(height: 20),
                      _buildTermsSectionTitle('Terms & Conditions', colors),
                      _termsParagraph(
                        colors,
                        'By using GENz+, you acknowledge and agree that the application functions solely as an IPTV media player.',
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        'GENz+ does not provide IPTV subscriptions, television channels, movies, TV series, or any streaming content. Users are solely responsible for the playlists, accounts, and streaming sources they choose to add and for ensuring they have the legal rights to access such content.',
                      ),
                      const SizedBox(height: 20),
                      _buildTermsSectionTitle('Privacy Policy', colors),
                      _termsParagraph(colors, 'GENz+ respects your privacy.'),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        'The application does not collect, store, transmit, or share your personal information.',
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        "Your playlists, login details, favorites, and application settings are stored locally on your device only to provide the app's functionality. This information is never uploaded to our servers, and you may edit or delete it at any time within the app.",
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        'GENz+ does not use advertising, analytics, or tracking services.',
                      ),
                      const SizedBox(height: 20),
                      _buildTermsSectionTitle('Important Disclaimer', colors),
                      _termsParagraph(colors, 'GENz+ is a media player only.'),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        'The application does not host, create, distribute, sell, or promote any television channels, movies, TV shows, or IPTV subscriptions.',
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        'GENz+ does not include any content or playlists. All playlists and streaming sources are provided solely by the user. Users are responsible for ensuring that their use of the application complies with all applicable laws and copyright regulations.',
                      ),
                      const SizedBox(height: 20),
                      _buildTermsSectionTitle('Contact GENz+', colors),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () async {
                          final url = Uri.parse('https://zaid000.xyz/GenzT&P.html');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: LinearGradient(colors: colors.brandGradient),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.language_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Contact Us',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTermsSectionTitle(String title, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: colors.brandPrimary,
        ),
      ),
    );
  }

  Widget _termsParagraph(AppColors colors, String text) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 13,
        height: 1.5,
        color: colors.ink.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
    String? Function(String?)? validator,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colors.ink.withValues(alpha: 0.6),
              letterSpacing: 1.5,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          style: GoogleFonts.outfit(color: colors.ink, fontSize: 15),
          decoration: InputDecoration(
            filled: true,
            fillColor: colors.surface,
            hintText: hint,
            hintStyle: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.3), fontSize: 14),
            prefixIcon: Icon(
              icon,
              color: colors.brandPrimary.withValues(alpha: 0.7),
              size: 20,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      obscureText
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: colors.ink.withValues(alpha: 0.38),
                      size: 20,
                    ),
                    onPressed: onTogglePassword,
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(
                color: colors.border,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(
                color: colors.brandPrimary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(color: colors.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(color: colors.error, width: 1.5),
            ),
            errorStyle: GoogleFonts.outfit(
              color: colors.error,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
