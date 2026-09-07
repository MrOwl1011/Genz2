import 'package:flutter_test/flutter_test.dart';
import 'package:genz/core/resume_season.dart';
import 'package:genz/providers/user_prefs_provider.dart';

HistoryItem item({
  required String id,
  required Object seriesId,
  required Object season,
  required DateTime watched,
  MediaType type = MediaType.series,
}) {
  return HistoryItem(
    id: id,
    title: id,
    posterUrl: '',
    type: type,
    positionMilliseconds: 1000,
    durationMilliseconds: 60000,
    rawData: {'series_id': seriesId, 'season': season},
    lastWatched: watched,
  );
}

void main() {
  final t0 = DateTime(2026, 1, 1);

  test('returns the season of the most recently watched episode', () {
    final history = [
      item(id: 'a', seriesId: 12, season: 5, watched: t0.add(const Duration(days: 2))),
      item(id: 'b', seriesId: 12, season: 2, watched: t0),
    ];
    expect(
      resumeSeasonFor(history: history, seriesId: 12, availableSeasons: [1, 2, 5]),
      5,
    );
  });

  test('ignores other series', () {
    final history = [item(id: 'a', seriesId: 99, season: 7, watched: t0)];
    expect(
      resumeSeasonFor(history: history, seriesId: 12, availableSeasons: [1, 7]),
      isNull,
    );
  });

  test('matches when series_id was stored as a string', () {
    final history = [item(id: 'a', seriesId: '12', season: 3, watched: t0)];
    expect(
      resumeSeasonFor(history: history, seriesId: 12, availableSeasons: [1, 3]),
      3,
    );
  });

  test('parses a season stored as a string', () {
    final history = [item(id: 'a', seriesId: 12, season: '4', watched: t0)];
    expect(
      resumeSeasonFor(history: history, seriesId: 12, availableSeasons: [1, 4]),
      4,
    );
  });

  test('skips a season the provider no longer lists', () {
    final history = [
      item(id: 'a', seriesId: 12, season: 9, watched: t0.add(const Duration(days: 1))),
      item(id: 'b', seriesId: 12, season: 2, watched: t0),
    ];
    expect(
      resumeSeasonFor(history: history, seriesId: 12, availableSeasons: [1, 2]),
      2,
    );
  });

  test('ignores movies that happen to carry a series_id', () {
    final history = [
      item(id: 'a', seriesId: 12, season: 6, watched: t0, type: MediaType.movie),
    ];
    expect(
      resumeSeasonFor(history: history, seriesId: 12, availableSeasons: [1, 6]),
      isNull,
    );
  });

  test('returns null for an unwatched series', () {
    expect(
      resumeSeasonFor(history: const [], seriesId: 12, availableSeasons: [1, 2]),
      isNull,
    );
  });
}
