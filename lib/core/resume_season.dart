import '../providers/user_prefs_provider.dart';

/// The season a viewer is partway through for [seriesId], or null if they
/// have not started this series.
///
/// Opening a series from Continue Watching and landing on season 1 is wrong
/// when the episode in that row is from season 5 — the viewer then has to
/// pick the season they were already watching before they can carry on.
///
/// Shared by the phone and ten-foot detail screens rather than implemented
/// twice: both store the same `season` and `series_id` keys in a history
/// item's rawData when an episode starts playing, so the same lookup serves
/// both and the two cannot drift apart.
///
/// [history] is expected newest-first, which is how UserPrefsProvider keeps
/// it (see its sort on lastWatched), so the first match is the most recently
/// watched episode of this series.
///
/// [availableSeasons] guards against returning a season the provider no
/// longer lists — a panel can drop or renumber seasons between sessions, and
/// selecting one that isn't there would render an empty episode list.
int? resumeSeasonFor({
  required List<HistoryItem> history,
  required int seriesId,
  required Iterable<int> availableSeasons,
}) {
  final target = seriesId.toString();

  for (final item in history) {
    if (item.type != MediaType.series) {
      continue;
    }
    // Compared as strings: series_id arrives as an int from the episode
    // builders but as a string from some of the history-restore paths.
    if (item.rawData['series_id']?.toString() != target) {
      continue;
    }

    final raw = item.rawData['season'];
    final season = raw is int ? raw : int.tryParse('$raw');
    if (season != null && availableSeasons.contains(season)) {
      return season;
    }
  }

  return null;
}
