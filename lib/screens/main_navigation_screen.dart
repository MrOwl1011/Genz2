import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import '../widgets/glass.dart';
import '../widgets/tv_focusable.dart';
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
    // Chrome tier, radius 18 rather than a 30pt capsule: a fully rounded bar
    // reads as a floating widget, while a soft rectangle reads as chrome the
    // content is passing beneath — which is what it is.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Glass(
        tier: GlassTier.chrome,
        radius: BorderRadius.circular(18),
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                0,
                isArabic ? 'الرئيسية' : 'Home',
                icon: Icons.home_rounded,
              ),
              _buildNavItem(
                1,
                isArabic ? 'مباشر' : 'Live',
                icon: Icons.sensors_rounded,
              ),
              _buildNavItem(
                2,
                isArabic ? 'أفلام' : 'Movies',
                icon: Icons.movie_creation_outlined,
              ),
              _buildNavItem(
                3,
                isArabic ? 'مسلسلات' : 'Series',
                icon: Icons.video_library_outlined,
              ),
              _buildNavItem(
                4,
                isArabic ? 'المزيد' : 'More',
                icon: Icons.menu_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String label, {IconData? icon}) {
    final isSelected = _currentIndex == index;
    final colors = context.colors;
    final activeColor = colors.brandPrimary;
    final inactiveColor = colors.ink.withValues(alpha: 0.38);

    // A 3x18 bar above the icon, not a filled pill behind it. The pill is a
    // Material default and reads immediately as an unstyled Flutter app; every
    // benchmark app marks the active tab with a rule or nothing at all.
    return TvFocusable(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 9),
            Icon(
              icon,
              color: isSelected ? colors.ink : inactiveColor,
              size: 22,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: AppType.meta(
                isSelected ? colors.ink : inactiveColor,
              ).copyWith(fontSize: 9.5, letterSpacing: 0.9),
            ),
          ],
        ),
      ),
    );
  }
}
