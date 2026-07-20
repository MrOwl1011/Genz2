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

  static const List<Color> themeColors = [
    Color(0xFFE50914), // Red (Default)
    Color(0xFFE91E63), // Pink
    Color(0xFF2196F3), // Blue
    Color(0xFF4CAF50), // Green
    Color(0xFF9C27B0), // Purple
  ];

  static const List<Color> themeSecondaryColors = [
    Color(0xFF881014), // Dark Red
    Color(0xFF880E4F), // Dark Pink
    Color(0xFF0D47A1), // Dark Blue
    Color(0xFF1B5E20), // Dark Green
    Color(0xFF4A148C), // Dark Purple
  ];

  @override
  Widget build(BuildContext context) {
    final userPrefs = Provider.of<UserPrefsProvider>(context);
    final locale = Locale(userPrefs.locale);
    final int colorIndex = userPrefs.themeColorIndex;
    final primaryColor = themeColors[colorIndex >= 0 && colorIndex < themeColors.length ? colorIndex : 0];
    final secondaryColor = themeSecondaryColors[colorIndex >= 0 && colorIndex < themeSecondaryColors.length ? colorIndex : 0];

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
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0002),
        primaryColor: primaryColor,
        colorScheme: ColorScheme.dark(
          primary: primaryColor,
          secondary: secondaryColor,
          surface: const Color(0xFF160103),
        ),
        useMaterial3: true,
      ),
      home: const AuthRootHandler(),
    );
  }
}

class AuthRootHandler extends StatelessWidget {
  const AuthRootHandler({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    // Splash while auto-login check
    if (auth.isInitializing) {
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
                Color(0xFF000000),
              ],
            ),
          ),
          child: const Center(
            child: SizedBox(
              width: 55,
              height: 55,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
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
