import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/content_provider.dart';
import 'providers/user_prefs_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/playlists_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Hide Android system bars (nav + status) for immersive IPTV experience.
  // immersiveSticky auto-re-hides after user swipe. Compatible with Android 10+.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final userPrefs = UserPrefsProvider();
  await userPrefs.init();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(userPrefs)),
          ChangeNotifierProvider.value(value: userPrefs),
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

class AuthRootHandler extends StatelessWidget {
  const AuthRootHandler({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final colors = context.colors;

    // Splash while auto-login check
    if (auth.isInitializing) {
      return Scaffold(
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
    }

    if (auth.isAuthenticated) {
      return const MainNavigationScreen();
    } else if (auth.hasSavedPlaylists) {
      return const PlaylistsScreen();
    } else {
      return const LoginScreen();
    }
  }
}
