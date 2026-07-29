import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/content_provider.dart';
import 'providers/downloads_provider.dart';
import 'providers/user_prefs_provider.dart';
import 'screens/downloads_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/playlists_screen.dart';
import 'services/connectivity_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hide Android system bars (nav + status) for immersive IPTV experience.
  // immersiveSticky auto-re-hides after user swipe. Compatible with Android 10+.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final userPrefs = UserPrefsProvider();
  await userPrefs.init();
  final downloads = DownloadsProvider();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(userPrefs, downloads)),
          ChangeNotifierProvider.value(value: userPrefs),
          ChangeNotifierProvider.value(value: downloads),
        ChangeNotifierProxyProvider<AuthProvider, ContentProvider>(
          create: (_) => ContentProvider(),
          update: (_, auth, content) {
            if (auth.isAuthenticated) {
              content!.setCredentials(
                auth.serverUrl,
                auth.username,
                auth.password,
              );
            } else {
              content!.reset();
            }
            return content;
          },
        ),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final userPrefs = Provider.of<UserPrefsProvider>(context);
    final locale = Locale(userPrefs.locale);

    return MaterialApp(
      title: 'NX IPTV',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: userPrefs.themeMode,
      home: const AuthRootHandler(),
    );
  }
}

class AuthRootHandler extends StatefulWidget {
  const AuthRootHandler({super.key});

  @override
  State<AuthRootHandler> createState() => _AuthRootHandlerState();
}

class _AuthRootHandlerState extends State<AuthRootHandler> {
  // null while the one-shot startup check is still running.
  bool? _hasInternet;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final hasInternet = await ConnectivityService.hasConnection();
    if (mounted) setState(() => _hasInternet = hasInternet);
  }

  Future<void> _onRetry() async {
    setState(() => _isRetrying = true);
    final hasInternet = await ConnectivityService.hasConnection();
    if (!mounted) return;
    setState(() {
      _hasInternet = hasInternet;
      _isRetrying = false;
    });

    if (hasInternet) {
      // Auto-login gives up (rather than hanging) when it hits a network
      // error, so if that happened while we were offline, give it another
      // shot now that connectivity is back instead of leaving the user
      // stuck on the account switcher / login screen.
      final auth = context.read<AuthProvider>();
      if (!auth.isAuthenticated && auth.hasSavedPlaylists) {
        auth.checkAutoLogin();
      }
    }
  }

  void _goToDownloads() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DownloadsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final colors = context.colors;

    Widget content;
    if (auth.isInitializing) {
      // Splash while auto-login check
      content = Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.backgroundGradient,
            ),
          ),
          child: Center(
            child: SizedBox(
              width: 55,
              height: 55,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
                strokeWidth: 3.5,
              ),
            ),
          ),
        ),
      );
    } else if (auth.isAuthenticated) {
      content = const MainNavigationScreen();
    } else if (auth.hasSavedPlaylists) {
      content = const PlaylistsScreen();
    } else {
      content = const LoginScreen();
    }

    // Gated on the initial auto-login pass having settled too, so the
    // "no internet" popup doesn't flash in ahead of / on top of the splash.
    final showNoInternetGate = !auth.isInitializing && _hasInternet == false;

    return Stack(
      children: [
        content,
        if (showNoInternetGate) _buildNoInternetGate(colors),
      ],
    );
  }

  Widget _buildNoInternetGate(AppColors colors) {
    return PopScope(
      canPop: false,
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: colors.brandPrimary.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wifi_off_rounded, color: colors.error, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  'No Internet Connection',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: colors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "You're offline. Connect to the internet to load live TV, "
                  "movies and series, or watch what you've already downloaded.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: colors.ink.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),

                // Retry button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isRetrying ? null : _onRetry,
                    icon: _isRetrying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                    label: Text(
                      'Retry',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.brandPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Go to Downloads button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _goToDownloads,
                    icon: Icon(
                      Icons.download_done_rounded,
                      color: colors.ink.withValues(alpha: 0.7),
                      size: 20,
                    ),
                    label: Text(
                      'Go to Downloads',
                      style: GoogleFonts.outfit(
                        color: colors.ink.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.ink.withValues(alpha: 0.24)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
