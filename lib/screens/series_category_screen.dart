import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/content_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../widgets/category_layout.dart';
import '../widgets/category_card.dart'; // for CategoryType
import 'series_screen.dart';

class SeriesCategoryScreen extends StatelessWidget {
  const SeriesCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentProvider>();
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';

    return CategoryLayout(
      title: isArabic ? 'مسلسلات' : 'SERIES',
      categories: content.seriesCategories,
      type: CategoryType.series,
      isLoading: content.isLoadingSeries,
      error: content.seriesError,
      onRetry: () => content.loadSeriesCategories(),
      onCategoryTap: (category) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SeriesScreen(category: category)),
        );
      },
      tabs: isArabic
          ? const ['الكل', 'المفضلة', 'جديد']
          : const ['All', 'Liked', 'New'],
    );
  }
}
