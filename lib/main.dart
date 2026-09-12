import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:window_manager/window_manager.dart' show windowManager;

import 'package:provider/provider.dart';
import 'app_root.dart';
import 'core/build_flavor.dart';
import 'core/error_fallback.dart';
import 'core/hive/hive_boxes.dart';
import 'features/profiles/presentation/providers/profile_provider.dart';
import 'features/sync/services/sync_manager.dart';
import 'providers/auth_provider.dart';
import 'providers/content_provider.dart';
import 'providers/downloads_provider.dart';
import 'providers/user_prefs_provider.dart';
import 'screens/main_navigation_screen.dart';
import 'theme/app_theme.dart';
import 'tv/screens/tv_home_screen.dart';

/// Phone/tablet entry point — the `phone` Android product flavor, and (see
/// [initIsTv]) the *only* entry point iOS ever uses, iPad included: there is
/// no iOS equivalent of Android's separate `tv` flavor/binary, so an iPad
/// runs this exact same build and gets switched into the TV UI at runtime
/// instead of at compile time. See [main_tv.dart] for Android TV's own,
/// still entirely separate, entry point/binary — nothing here changes what
/// that one does.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorFallback();
  initIsTv();

  // Desktop plays through libmpv (see MediaKitBackend), which needs this
  // once before the first Player is constructed. Deliberately not called on
  // mobile: those platforms use VLCKit/ExoPlayer instead and don't bundle
  // media_kit's native libraries, so initializing it there would be loading
  // something that isn't shipped.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    MediaKit.ensureInitialized();
    // Needed before anything asks the window to go fullscreen — see the
    // player's fullscreen button. Desktop only: on mobile the app already
    // owns the whole screen and this plugin is not built at all.
    await windowManager.ensureInitialized();
  }

  if (kIsTv) {
    // Mirrors main_tv.dart's own startup: an iPad running in TV mode gets
    // the same landscape-locked, immersive treatment Android TV gets,
    // since it's presenting the same remote/D-pad-oriented UI — see
    // build_flavor.dart's doc comment for why kIsTv is true here at all.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    // Normal edge-to-edge mode: status bar (and Android nav bar) stay visible
    // everywhere except the player screen, which switches to immersiveSticky
    // itself while watching and restores this mode on exit.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  await HiveBoxes.init();
  SyncManager.instance.start();

  final userPrefs = UserPrefsProvider();
  await userPrefs.init();
  final downloads = DownloadsProvider();
  final profileProvider = ProfileProvider(userPrefs);

  AppRoot.homeBuilder = (_) =>
      kIsTv ? const TvHomeScreen() : const MainNavigationScreen();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(userPrefs, downloads, profileProvider),
        ),
        ChangeNotifierProvider.value(value: userPrefs),
        ChangeNotifierProvider.value(value: downloads),
        ChangeNotifierProvider.value(value: profileProvider),
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
      title: kIsTv ? 'GenZ+ TV' : 'NX IPTV',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: kIsTv ? AppTheme.tv : AppTheme.light,
      darkTheme: kIsTv ? AppTheme.tv : AppTheme.dark,
      // Same reasoning as main_tv.dart: a TV-style UI viewed at a distance
      // wants the one deliberately-tuned-for-that palette regardless of the
      // device's system theme setting — true for an iPad in TV mode too.
      themeMode: kIsTv ? ThemeMode.dark : userPrefs.themeMode,
      home: const AppRoot(),
    );
  }
}
