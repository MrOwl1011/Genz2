import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_root.dart';
import '../core/build_flavor.dart' show kIsTv;
import '../providers/auth_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/dialog_buttons.dart';
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

  // Explicit FocusNodes for the 3 visible fields plus the submit button —
  // needed so D-pad up/down can move between them deterministically (see
  // _handleTvDpadKey) instead of relying on Flutter's default
  // directional-focus heuristics, which never fire at all while a text
  // field is focused (see _handleTvDpadKey's doc comment) — which is what
  // left a TV remote stuck the moment it entered any field, with no way to
  // leave it at all.
  final _serverFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _connectButtonFocusNode = FocusNode();

  bool _obscurePassword = true;

  // TV only: Android auto-opens the on-screen keyboard the instant a text
  // field gains focus — including when the D-pad merely navigates onto it —
  // and that overlay then swallows every further D-pad press for moving
  // between its own keys, not our fields, until BACK is pressed. Real TV
  // apps avoid this by keeping fields read-only (no IME) until the user
  // explicitly presses select/OK on them; this tracks which single field (if
  // any) is currently "activated" that way. Always null and unused on phone.
  FocusNode? _activeEditingNode;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleTvDpadKey);
    if (kIsTv) {
      for (final node in [
        _serverFocusNode,
        _usernameFocusNode,
        _passwordFocusNode,
      ]) {
        node.addListener(() {
          if (!node.hasFocus && _activeEditingNode == node) {
            setState(() => _activeEditingNode = null);
          }
        });
      }
    }
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
        if (auth.playlistName.isNotEmpty &&
            auth.playlistName != 'My Playlist') {
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
    HardwareKeyboard.instance.removeHandler(_handleTvDpadKey);
    _nameController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _serverFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _connectButtonFocusNode.dispose();
    super.dispose();
  }

  /// Moves focus between the login fields (and on to the submit button) on
  /// D-pad up/down — the only reliable place to do this on a TV remote.
  ///
  /// Flutter's built-in directional-focus shortcuts (arrow keys moving focus
  /// to the next widget) are explicitly disabled while a text field has
  /// focus: `EditableText` binds arrow keys to `DirectionalFocusIntent`
  /// constructed with `ignoreTextFields: true`, and that binding lives
  /// *inside* the text field's own widget tree, closer to the focused leaf
  /// than anything wrapped around the outside of it — so a `Focus` or
  /// `Shortcuts` widget wrapping a `TextFormField` never even sees the key
  /// event; the field's own handling claims it first and does nothing with
  /// it. A `HardwareKeyboard` handler sits one level below all of that — it
  /// sees every key press application-wide regardless of the focus tree —
  /// which is the only layer left that can actually move focus here.
  bool _handleTvDpadKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final focused = FocusManager.instance.primaryFocus;

    // Explicit select/OK on a still-read-only field is what's allowed to
    // open the on-screen keyboard (see _activeEditingNode) — everything else
    // in this handler is just moving focus around between fields, which
    // must NOT trigger it.
    if (kIsTv &&
        (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) &&
        (focused == _serverFocusNode ||
            focused == _usernameFocusNode ||
            focused == _passwordFocusNode) &&
        _activeEditingNode != focused) {
      setState(() => _activeEditingNode = focused);
      return true;
    }

    // Left/Right on the password field toggles show/hide instead of moving
    // focus anywhere — the eye icon is excluded from TV focus traversal
    // (see its ExcludeFocus wrapper below) specifically so this is the one
    // and only way to reach it by remote, rather than leaving it as a
    // second, separately-focusable target the D-pad could land on
    // unpredictably via default traversal.
    if (kIsTv &&
        focused == _passwordFocusNode &&
        _activeEditingNode != _passwordFocusNode &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      setState(() => _obscurePassword = !_obscurePassword);
      return true;
    }

    FocusNode? target;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (focused == _serverFocusNode) {
        target = _usernameFocusNode;
      } else if (focused == _usernameFocusNode) {
        target = _passwordFocusNode;
      } else if (focused == _passwordFocusNode) {
        target = _connectButtonFocusNode;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (focused == _connectButtonFocusNode) {
        target = _passwordFocusNode;
      } else if (focused == _passwordFocusNode) {
        target = _usernameFocusNode;
      } else if (focused == _usernameFocusNode) {
        target = _serverFocusNode;
      }
    }
    if (target == null) return false;
    target.requestFocus();
    return true;
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
        // Route back through AppRoot rather than straight to the home
        // screen — it reactively picks ProfilePickerScreen vs the home
        // screen based on ProfileProvider.hasActiveProfile, which right
        // after a login is almost always false (a profile hasn't been
        // chosen yet — see AuthProvider._connectBackendAndProfiles, which
        // deliberately doesn't auto-select one). Jumping straight to the
        // home screen skipped the profile picker entirely, and for an
        // account with existing profiles, skipped profile-scoped storage
        // too (UserPrefsProvider never got told which profile to use).
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AppRoot()),
          (route) => false,
        );
      } else {
        // Show styled error dialog if login fails
        final isArabic =
            Provider.of<UserPrefsProvider>(context, listen: false).locale ==
            'ar';
        _showErrorDialog(
          auth.errorMessage ??
              (isArabic ? 'حدث خطأ غير معروف' : 'An unknown error occurred'),
        );
      }
    }
  }

  void _showErrorDialog(String message) {
    final colors = context.colors;
    final isArabic =
        Provider.of<UserPrefsProvider>(context, listen: false).locale == 'ar';
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
              isArabic ? 'خطأ في الاتصال' : 'Connection Error',
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
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          DialogPrimaryButton(
            label: isArabic ? 'موافق' : 'OK',
            color: colors.error,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';

    // If auto-logged in, navigate automatically — through AppRoot, same
    // reasoning as _handleLogin() above.
    if (auth.isAuthenticated && !auth.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AppRoot()),
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
              child: Align(
                // SingleChildScrollView hands its child a tight width (it
                // matches the viewport), so ConstrainedBox alone can't
                // shrink below that — Align gives it a loose constraint
                // first so the maxWidth below actually takes effect, then
                // centers the narrower result.
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  // On TV this screen otherwise stretches edge-to-edge
                  // across a 1920-wide landscape panel — pill fields and a
                  // gradient button that wide read as an oversized
                  // placeholder, not a real form. Phone keeps its existing
                  // unconstrained width (double.infinity is a no-op there,
                  // same layout as always).
                  constraints: BoxConstraints(
                    maxWidth: kIsTv ? 440 : double.infinity,
                  ),
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
                                  fontSize: kIsTv ? 34 : 50,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  color: colors.brandPrimary,
                                  letterSpacing: 2,
                                ),
                              ),
                              Text(
                                '+',
                                style: GoogleFonts.outfit(
                                  fontSize: kIsTv ? 34 : 50,
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
                            isArabic
                                ? 'عالمك الترفيهي الأمثل'
                                : 'YOUR ULTIMATE ENTERTAINMENT WORLD',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: GoogleFonts.outfit(
                              fontSize: kIsTv ? 9 : 10,
                              fontWeight: FontWeight.w600,
                              color: colors.ink.withValues(alpha: 0.38),
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      // On TV the whole form has to fit an 1080-tall landscape
                      // panel without scrolling (a D-pad has no reliable way
                      // to trigger a scroll here) — the phone's generous
                      // 48px breathing room becomes a much tighter budget.
                      SizedBox(height: kIsTv ? 20 : 48),

                      // States plainly, on the first screen anyone sees,
                      // that this is a player and brings no catalogue of
                      // its own — the user supplies their own service, the
                      // same way VLC does. This is the single most
                      // important thing for a reviewer to understand about
                      // the app, and burying it in the Terms page meant it
                      // was read only after the app already looked like an
                      // empty shell.
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: kIsTv ? 8 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: colors.ink.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.ink.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: kIsTv ? 14 : 18,
                              color: colors.ink.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isArabic
                                    ? 'يعمل GENz+ كمشغّل فقط ولا يوفّر أي قنوات أو أفلام. '
                                          'أدخل بيانات خدمتك الخاصة للمتابعة.'
                                    : 'GENz+ is a player only. It provides no channels, '
                                          'movies or playlists — sign in with your own '
                                          'service to continue.',
                                style: GoogleFonts.outfit(
                                  color: colors.ink.withValues(alpha: 0.7),
                                  fontSize: kIsTv ? 10.5 : 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: kIsTv ? 14 : 20),

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
                              label: isArabic ? 'رابط الخادم' : 'Server URL',
                              hint: 'http://example.com:8080',
                              icon: Icons.dns_outlined,
                              focusNode: _serverFocusNode,
                              nextFocusNode: _usernameFocusNode,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return isArabic
                                      ? 'رابط الخادم مطلوب'
                                      : 'Server URL is required';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: kIsTv ? 8 : 20),

                            // Username Input
                            _buildInputField(
                              controller: _usernameController,
                              label: isArabic ? 'المستخدم' : 'Username',
                              hint: isArabic
                                  ? 'أدخل اسم المستخدم'
                                  : 'Enter username',
                              icon: Icons.person_outline_rounded,
                              focusNode: _usernameFocusNode,
                              nextFocusNode: _passwordFocusNode,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return isArabic
                                      ? 'اسم المستخدم مطلوب'
                                      : 'Username is required';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: kIsTv ? 8 : 20),

                            // Password Input
                            _buildInputField(
                              controller: _passwordController,
                              label: isArabic ? 'كلمة المرور' : 'Password',
                              hint: isArabic
                                  ? 'أدخل كلمة المرور'
                                  : 'Enter password',
                              icon: Icons.lock_outline_rounded,
                              isPassword: true,
                              obscureText: _obscurePassword,
                              focusNode: _passwordFocusNode,
                              textInputAction: TextInputAction.done,
                              onTogglePassword: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return isArabic
                                      ? 'كلمة المرور مطلوبة'
                                      : 'Password is required';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: kIsTv ? 8 : 12),
                            _buildTermsNotice(isArabic),
                            SizedBox(height: kIsTv ? 14 : 24),

                            // Login Action Button or Loading Indicator
                            auth.isLoading
                                ? Center(
                                    child: SizedBox(
                                      width: 50,
                                      height: 50,
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              colors.brandPrimary,
                                            ),
                                        strokeWidth: 3.5,
                                      ),
                                    ),
                                  )
                                : ListenableBuilder(
                                    listenable: _connectButtonFocusNode,
                                    builder: (context, child) {
                                      final focused =
                                          _connectButtonFocusNode.hasFocus;
                                      return AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 150,
                                        ),
                                        // Shorter and less shouty on TV — full
                                        // phone size inside the now-narrower
                                        // TV-width form read as an oversized
                                        // placeholder button rather than a
                                        // real one.
                                        height: kIsTv ? 40 : 58,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            kIsTv ? 20 : 30,
                                          ),
                                          gradient: LinearGradient(
                                            colors: colors.brandGradient,
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                          border: focused
                                              ? Border.all(
                                                  color: colors.brandAccent,
                                                  width: 3,
                                                )
                                              : null,
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  (focused
                                                          ? colors.brandAccent
                                                          : colors.brandPrimary)
                                                      .withValues(
                                                        alpha: focused
                                                            ? 0.6
                                                            : 0.4,
                                                      ),
                                              blurRadius: focused ? 20 : 15,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: child,
                                      );
                                    },
                                    child: ElevatedButton(
                                      focusNode: _connectButtonFocusNode,
                                      onPressed: _handleLogin,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            kIsTv ? 20 : 30,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        isArabic ? 'اتصل الآن' : 'CONNECT NOW',
                                        style: GoogleFonts.outfit(
                                          fontSize: kIsTv ? 13 : 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: kIsTv ? 1.5 : 2,
                                        ),
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),

                      SizedBox(height: kIsTv ? 10 : 16),

                      // Users Button — opens the saved playlists switcher
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PlaylistsScreen(),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.switch_account_rounded,
                          color: colors.ink.withValues(alpha: 0.7),
                          size: kIsTv ? 16 : 20,
                        ),
                        label: Text(
                          isArabic ? 'المستخدمون' : 'Users',
                          style: GoogleFonts.outfit(
                            color: colors.ink.withValues(alpha: 0.7),
                            fontSize: kIsTv ? 11 : 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: colors.ink.withValues(alpha: 0.05),
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: kIsTv ? 5 : 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: colors.ink.withValues(alpha: 0.1),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTermsNotice(bool isArabic) {
    final colors = context.colors;
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: GoogleFonts.outfit(
          fontSize: 12,
          color: colors.ink.withValues(alpha: 0.54),
        ),
        children: [
          TextSpan(
            text: isArabic
                ? 'بالمتابعة، أنت توافق على '
                : 'By continuing, you agree to our ',
          ),
          TextSpan(
            text: isArabic
                ? 'الشروط وسياسة الخصوصية'
                : 'Terms & Privacy Policy',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colors.brandPrimary,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _showTermsDialog(isArabic),
          ),
        ],
      ),
    );
  }

  void _showTermsDialog(bool isArabic) {
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
                        isArabic
                            ? 'الشروط وسياسة الخصوصية'
                            : 'Terms & Privacy Policy',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: colors.ink.withValues(alpha: 0.7),
                      ),
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
                        isArabic ? 'عن GENz+' : 'About GENz+',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colors.brandPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'تطبيق GENz+ هو مشغل وسائط IPTV حديث مصمم لتقديم تجربة مشاهدة سلسة وسريعة وعالية الجودة. يدعم التطبيق قوائم التشغيل التي يوفرها المستخدم، مما يتيح لك تنظيم البث المباشر والأفلام والمسلسلات والاستمتاع بها في مكان واحد.'
                            : 'GENz+ is a modern IPTV media player designed to provide a smooth, fast, and premium viewing experience. The app supports user-provided playlists, allowing you to organize and enjoy your live TV, movies, and series in one place.',
                      ),
                      const SizedBox(height: 20),
                      _buildTermsSectionTitle(
                        isArabic ? 'الشروط والأحكام' : 'Terms & Conditions',
                        colors,
                      ),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'باستخدامك لتطبيق GENz+، فإنك تقر وتوافق على أن التطبيق يعمل فقط كمشغل وسائط IPTV.'
                            : 'By using GENz+, you acknowledge and agree that the application functions solely as an IPTV media player.',
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'لا يوفر GENz+ اشتراكات IPTV أو قنوات تلفزيونية أو أفلاماً أو مسلسلات أو أي محتوى بث. يتحمل المستخدمون وحدهم مسؤولية قوائم التشغيل والحسابات ومصادر البث التي يختارون إضافتها، ومسؤولية التأكد من امتلاكهم الحق القانوني للوصول إلى هذا المحتوى.'
                            : 'GENz+ does not provide IPTV subscriptions, television channels, movies, TV series, or any streaming content. Users are solely responsible for the playlists, accounts, and streaming sources they choose to add and for ensuring they have the legal rights to access such content.',
                      ),
                      const SizedBox(height: 20),
                      _buildTermsSectionTitle(
                        isArabic ? 'سياسة الخصوصية' : 'Privacy Policy',
                        colors,
                      ),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'يحترم GENz+ خصوصيتك.'
                            : 'GENz+ respects your privacy.',
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'لا يقوم التطبيق بجمع أو تخزين أو نقل أو مشاركة معلوماتك الشخصية.'
                            : 'The application does not collect, store, transmit, or share your personal information.',
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'يتم تخزين قوائم التشغيل وبيانات تسجيل الدخول والمفضلة وإعدادات التطبيق محلياً على جهازك فقط لتوفير وظائف التطبيق. لا يتم رفع هذه المعلومات إلى خوادمنا أبداً، ويمكنك تعديلها أو حذفها في أي وقت داخل التطبيق.'
                            : "Your playlists, login details, favorites, and application settings are stored locally on your device only to provide the app's functionality. This information is never uploaded to our servers, and you may edit or delete it at any time within the app.",
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'لا يستخدم GENz+ أي خدمات إعلانات أو تحليلات أو تتبع.'
                            : 'GENz+ does not use advertising, analytics, or tracking services.',
                      ),
                      const SizedBox(height: 20),
                      _buildTermsSectionTitle(
                        isArabic ? 'إخلاء مسؤولية هام' : 'Important Disclaimer',
                        colors,
                      ),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'GENz+ هو مشغل وسائط فقط.'
                            : 'GENz+ is a media player only.',
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'لا يستضيف التطبيق أو ينشئ أو يوزع أو يبيع أو يروج لأي قنوات تلفزيونية أو أفلام أو مسلسلات أو اشتراكات IPTV.'
                            : 'The application does not host, create, distribute, sell, or promote any television channels, movies, TV shows, or IPTV subscriptions.',
                      ),
                      const SizedBox(height: 8),
                      _termsParagraph(
                        colors,
                        isArabic
                            ? 'لا يتضمن GENz+ أي محتوى أو قوائم تشغيل. جميع قوائم التشغيل ومصادر البث يوفرها المستخدم وحده. يتحمل المستخدمون مسؤولية التأكد من أن استخدامهم للتطبيق يتوافق مع جميع القوانين وأنظمة حقوق النشر المعمول بها.'
                            : 'GENz+ does not include any content or playlists. All playlists and streaming sources are provided solely by the user. Users are responsible for ensuring that their use of the application complies with all applicable laws and copyright regulations.',
                      ),
                      const SizedBox(height: 20),
                      _buildTermsSectionTitle(
                        isArabic ? 'تواصل مع GENz+' : 'Contact GENz+',
                        colors,
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () async {
                          final url = Uri.parse(
                            'https://zaid000.xyz/GenzT&P.html',
                          );
                          if (await canLaunchUrl(url)) {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: LinearGradient(
                              colors: colors.brandGradient,
                            ),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.language_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isArabic ? 'تواصل معنا' : 'Contact Us',
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
    FocusNode? focusNode,
    FocusNode? nextFocusNode,
    TextInputAction? textInputAction,
    // Fires instead of moving to nextFocusNode when this is the last field
    // — the Password field submits the whole form on its IME "Done" action
    // rather than needing the D-pad to separately reach the button widget.
    VoidCallback? onSubmit,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: kIsTv ? 4.0 : 8.0),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.outfit(
              fontSize: kIsTv ? 10 : 11,
              fontWeight: FontWeight.bold,
              color: colors.ink.withValues(alpha: 0.6),
              letterSpacing: 1.5,
            ),
          ),
        ),
        focusNode == null
            ? _buildTextFormField(
                colors: colors,
                controller: controller,
                hint: hint,
                icon: icon,
                isPassword: isPassword,
                obscureText: obscureText,
                onTogglePassword: onTogglePassword,
                validator: validator,
                focusNode: focusNode,
                textInputAction: textInputAction,
                nextFocusNode: nextFocusNode,
                onSubmit: onSubmit,
              )
            : ListenableBuilder(
                listenable: focusNode,
                builder: (context, child) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: focusNode.hasFocus
                          ? [
                              BoxShadow(
                                color: colors.brandAccent.withValues(
                                  alpha: 0.5,
                                ),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: child,
                  );
                },
                child: _buildTextFormField(
                  colors: colors,
                  controller: controller,
                  hint: hint,
                  icon: icon,
                  isPassword: isPassword,
                  obscureText: obscureText,
                  onTogglePassword: onTogglePassword,
                  validator: validator,
                  focusNode: focusNode,
                  textInputAction: textInputAction,
                  nextFocusNode: nextFocusNode,
                  onSubmit: onSubmit,
                ),
              ),
      ],
    );
  }

  Widget _buildTextFormField({
    required AppColors colors,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isPassword,
    required bool obscureText,
    required VoidCallback? onTogglePassword,
    required String? Function(String?)? validator,
    required FocusNode? focusNode,
    required TextInputAction? textInputAction,
    required FocusNode? nextFocusNode,
    VoidCallback? onSubmit,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      validator: validator,
      textInputAction: textInputAction,
      // TV: stays read-only (no on-screen keyboard) until the user
      // explicitly selects it — see _activeEditingNode. No-op on phone
      // (always false there), where tapping a field should open the
      // keyboard immediately as it always has.
      readOnly: kIsTv && focusNode != null && _activeEditingNode != focusNode,
      onFieldSubmitted: (_) {
        if (onSubmit != null) {
          onSubmit();
        } else if (nextFocusNode != null) {
          nextFocusNode.requestFocus();
        } else {
          focusNode?.unfocus();
        }
      },
      style: GoogleFonts.outfit(color: colors.ink, fontSize: kIsTv ? 13 : 15),
      decoration: InputDecoration(
        filled: true,
        fillColor: colors.surface,
        hintText: hint,
        hintStyle: GoogleFonts.outfit(
          color: colors.ink.withValues(alpha: 0.3),
          fontSize: kIsTv ? 12 : 14,
        ),
        prefixIcon: Icon(
          icon,
          color: colors.brandPrimary.withValues(alpha: 0.7),
          size: kIsTv ? 17 : 20,
        ),
        suffixIcon: isPassword
            ? ExcludeFocus(
                // On TV this is reachable only via Left/Right while the
                // password field itself has focus (see _handleTvDpadKey) —
                // excluded from the focus tree entirely there so it's never
                // a second, independently-reachable target the D-pad could
                // land on via default traversal. Phone keeps it as a normal
                // tappable icon.
                excluding: kIsTv,
                child: IconButton(
                  icon: Icon(
                    obscureText
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: colors.ink.withValues(alpha: 0.38),
                    size: kIsTv ? 17 : 20,
                  ),
                  onPressed: onTogglePassword,
                ),
              )
            : null,
        // On TV this is deliberately much shorter than the phone build's
        // thumb-friendly touch target — a remote-driven field doesn't need
        // the extra padding, and at the phone size a form of these read as
        // oversized inside the width-constrained TV layout above.
        contentPadding: EdgeInsets.symmetric(
          horizontal: kIsTv ? 16 : 20,
          vertical: kIsTv ? 7 : 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: colors.border, width: 1.5),
        ),
        // Thicker and brand-accent (not the dimmer brandPrimary) on TV —
        // the glow in _buildInputField's AnimatedContainer carries most of
        // the "this is focused" signal on the phone build already, but on
        // a 10-foot screen the border itself needs to read clearly too.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(
            color: kIsTv ? colors.brandAccent : colors.brandPrimary,
            width: kIsTv ? 2.5 : 1.5,
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
        errorStyle: GoogleFonts.outfit(color: colors.error, fontSize: 11),
      ),
    );
  }
}
