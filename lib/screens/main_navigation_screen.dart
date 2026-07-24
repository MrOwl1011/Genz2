import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'live_screen.dart'; // will update this next
import 'movies_category_screen.dart';
import 'series_category_screen.dart';
import 'more_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    LiveScreen(), // Will update live_screen.dart next to use Categories
    MoviesCategoryScreen(), // Using the new category screen for movies
    SeriesCategoryScreen(), // Using the new category screen for Series
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      extendBody: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.backgroundGradient,
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _screens[_currentIndex],
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _buildFloatingBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingBottomBar() {
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 75,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: colors.ink.withValues(alpha: 0.08),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, isArabic ? 'الرئيسية' : 'Home', isHomeLogo: true),
              _buildNavItem(1, isArabic ? 'مباشر' : 'Live', icon: Icons.sensors_rounded),
              _buildNavItem(2, isArabic ? 'أفلام' : 'Movies', icon: Icons.movie_creation_outlined),
              _buildNavItem(3, isArabic ? 'مسلسلات' : 'Series', icon: Icons.video_library_outlined),
              _buildNavItem(4, isArabic ? 'المزيد' : 'More', icon: Icons.menu_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    String label, {
    IconData? icon,
    bool isHomeLogo = false,
  }) {
    final isSelected = _currentIndex == index;
    final colors = context.colors;
    final activeColor = colors.brandPrimary;
    final inactiveColor = colors.ink.withValues(alpha: 0.38);

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isHomeLogo)
              Text(
                'NX',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: isSelected ? activeColor : inactiveColor,
                ),
              )
            else
              Icon(
                icon,
                color: isSelected ? activeColor : inactiveColor,
                size: 22,
              ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
