import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:provider/provider.dart';
import 'app_root.dart';
import 'core/error_fallback.dart';
import 'core/hive/hive_boxes.dart';
import 'features/profiles/presentation/providers/profile_provider.dart';
import 'features/sync/services/sync_manager.dart';
import 'providers/auth_provider.dart';
import 'providers/content_provider.dart';
import 'providers/downloads_provider.dart';
import 'providers/user_prefs_provider.dart';
import 'theme/app_theme.dart';
import 'tv/screens/tv_home_screen.dart';

/// Android TV entry point — the `tv` Android product flavor, a separate
/// installable app (own applicationId, own Play Console listing) from the
/// phone build in [main.dart]. Built with
/// `flutter build appbundle --flavor tv -t lib/main_tv.dart
/// --dart-define=IS_TV=true` (see android/app/build.gradle.kts and
/// lib/core/build_flavor.dart).
///
/// Shares everything below [AppRoot] with the phone entry point — same
/// providers, same data layer, same login/playlist/profile screens — and
/// diverges only in [AppRoot.homeBuilder] (this always shows [TvHomeScreen],
/// no runtime device check needed: the flavor itself is the signal) and the
/// startup orientation lock below, since a TV has no orientation to rotate
/// to in the first place.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorFallback();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await HiveBoxes.init();
  SyncManager.instance.start();

  final userPrefs = UserPrefsProvider();
  await userPrefs.init();
  final downloads = DownloadsProvider();
  final profileProvider = ProfileProvider(userPrefs);

  AppRoot.homeBuilder = (_) => const TvHomeScreen();

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
      child: const TvApp(),
    ),
  );
}

class TvApp extends StatelessWidget {
  const TvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final userPrefs = Provider.of<UserPrefsProvider>(context);
    final locale = Locale(userPrefs.locale);

    return MaterialApp(
      title: 'GenZ+ TV',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.tv,
      darkTheme: AppTheme.tv,
      // TV displays are viewed from across a room, at fixed brightness and
      // ambient light very different from a phone in someone's hand — the
      // light theme's low-contrast-on-purpose palette doesn't hold up there
      // the way it does up close, so the TV flavor is dark-only regardless
      // of the device's system theme setting.
      themeMode: ThemeMode.dark,
      home: const AppRoot(),
    );
  }
}
