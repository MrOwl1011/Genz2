import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import 'main_navigation_screen.dart';

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
        // Use pushAndRemoveUntil to reset the stack
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
          (route) => false,
        );
      } else {
        // Show styled error dialog if login fails
        _showErrorDialog(auth.errorMessage ?? 'An unknown error occurred');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E0306),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFE50914)),
            const SizedBox(width: 10),
            Text(
              'Connection Error',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: GoogleFonts.outfit(
                color: const Color(0xFFE50914),
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

    // If auto-logged in, navigate automatically
    if (auth.isAuthenticated && !auth.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
        );
      });
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF300408), // Premium Deep Red/Burgundy
              Color(0xFF0C0002), // Dark Crimson Black
              Color(0xFF030000), // Pure Black
            ],
            stops: [0.0, 0.5, 1.0],
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
                            'NX ',
                            style: GoogleFonts.outfit(
                              fontSize: 50,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFFE50914),
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            'IPTV',
                            style: GoogleFonts.outfit(
                              fontSize: 50,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'AD-FREE & STREAMLINED',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white38,
                          letterSpacing: 4,
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
                        // Playlist Name Input
                        _buildInputField(
                          controller: _nameController,
                          label: 'Playlist Name',
                          hint: 'e.g. My Home TV',
                          icon: Icons.tv_rounded,
                        ),
                        const SizedBox(height: 20),

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
                        const SizedBox(height: 32),

                        // Login Action Button or Loading Indicator
                        auth.isLoading
                            ? const Center(
                                child: SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFFE50914),
                                    ),
                                    strokeWidth: 3.5,
                                  ),
                                ),
                              )
                            : Container(
                                height: 58,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(30),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFE50914), // Bright red
                                      Color(0xFF900C12), // Deep red
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFE50914,
                                      ).withValues(alpha: 0.4),
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

                  const SizedBox(height: 24),
                  
                  // Contact Us Button
                  TextButton.icon(
                    onPressed: () async {
                      final url = Uri.parse('https://wa.me/96550507254');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.support_agent_rounded, color: Colors.white70, size: 20),
                    label: Text(
                      'Contact Us',
                      style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Colors.white10),
                      ),
                    ),
                  ),

                  // Bottom info banner
                  const SizedBox(height: 24),
                  Text(
                    'Xtream Codes API Authentication Player',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: Colors.white24,
                      fontWeight: FontWeight.w400,
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
              color: Colors.white60,
              letterSpacing: 1.5,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.45),
            hintText: hint,
            hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 14),
            prefixIcon: Icon(
              icon,
              color: const Color(0xFFE50914).withValues(alpha: 0.7),
              size: 20,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      obscureText
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.white38,
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
              borderSide: const BorderSide(
                color: Color(0xFF2C0A0D),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: const BorderSide(
                color: Color(0xFFE50914),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
            errorStyle: GoogleFonts.outfit(
              color: Colors.redAccent,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
