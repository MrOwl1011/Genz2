import 'xtream_models.dart';

class SearchResults {
  final List<XtreamVodStream> movies;
  final List<XtreamSeries> series;
  final List<XtreamLiveStream> liveStreams;

  SearchResults({
    required this.movies,
    required this.series,
    required this.liveStreams,
  });

  bool get isEmpty => movies.isEmpty && series.isEmpty && liveStreams.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
