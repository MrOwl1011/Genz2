import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/profiles/presentation/providers/profile_provider.dart';
import 'features/profiles/presentation/screens/profile_picker_screen.dart';
import 'providers/auth_provider.dart';
import 'screens/downloads_screen.dart';
import 'screens/login_screen.dart';
import 'screens/playlists_screen.dart';
import 'services/connectivity_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_type.dart';

/// The reactive root of the app, shared by both the phone and TV entry
/// points ([main.dart]/[main_tv.dart]): loading/no-internet gates, then
/// login → playlist switcher → profile picker → [homeBuilder]'s screen.
/// Everything above that point is identical for both flavors; only what's
/// shown once a profile is active differs (`MainNavigationScreen` vs
/// `TvHomeScreen`).
class AppRoot extends StatefulWidget {
  /// Which screen to show once a profile is active. Set exactly once, by
  /// `main()`/`main_tv.dart` before `runApp()` — not passed as a constructor
  /// parameter, because several shared screens (login, playlists, profile
  /// picker/edit) push `const AppRoot()` to reset to the app root after
  /// login/logout/profile changes, and none of them know or should need to
  /// know which flavor they're running in.
  static late final WidgetBuilder homeBuilder;

  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DownloadsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final profileProvider = context.watch<ProfileProvider>();
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
      final needsProfilePick = !profileProvider.hasActiveProfile;
      content = needsProfilePick
          ? const ProfilePickerScreen()
          : AppRoot.homeBuilder(context);
    } else if (auth.hasSavedPlaylists) {
      content = const PlaylistsScreen();
    } else {
      content = const LoginScreen();
    }

    // Gated on the initial auto-login pass having settled too, so the
    // "no internet" popup doesn't flash in ahead of / on top of the splash.
    final showNoInternetGate = !auth.isInitializing && _hasInternet == false;

    return Stack(
      children: [content, if (showNoInternetGate) _buildNoInternetGate(colors)],
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
                  child: Icon(
                    Icons.wifi_off_rounded,
                    color: colors.error,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No Internet Connection',
                  textAlign: TextAlign.center,
                  style: AppType.heading(colors.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  "You're offline. Connect to the internet to load live TV, "
                  "movies and series, or watch what you've already downloaded.",
                  textAlign: TextAlign.center,
                  style: AppType.body(colors.ink.withValues(alpha: 0.6)),
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                    label: Text(
                      'Retry',
                      style: AppType.cardTitle(Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.brandPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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
                      style: AppType.cardTitle(
                        colors.ink.withValues(alpha: 0.7),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: colors.ink.withValues(alpha: 0.24),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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
