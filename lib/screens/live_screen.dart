import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/content_provider.dart';
import '../widgets/category_layout.dart';
import '../widgets/category_card.dart'; // for CategoryType
import 'channels_screen.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentProvider>();

    return CategoryLayout(
      title: 'LIVE',
      categories: content.liveCategories,
      type: CategoryType.live,
      isLoading: content.isLoadingLive,
      error: content.liveError,
      onRetry: () => content.loadLiveCategories(),
      onCategoryTap: (category) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChannelsScreen(category: category)),
        );
      },
      tabs: const ['All', 'Liked'],
    );
  }
}
