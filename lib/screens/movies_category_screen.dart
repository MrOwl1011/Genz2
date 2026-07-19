import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/content_provider.dart';
import '../widgets/category_layout.dart';
import '../widgets/category_card.dart'; // for CategoryType
import 'movies_screen.dart';

class MoviesCategoryScreen extends StatelessWidget {
  const MoviesCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentProvider>();

    return CategoryLayout(
      title: 'MOVIES',
      categories: content.vodCategories,
      type: CategoryType.movie,
      isLoading: content.isLoadingVod,
      error: content.vodError,
      onRetry: () => content.loadVodCategories(),
      onCategoryTap: (category) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MoviesScreen(category: category)),
        );
      },
      tabs: const ['All', 'Liked', 'New'],
    );
  }
}
