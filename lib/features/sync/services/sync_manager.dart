import 'dart:async';
import 'package:flutter/widgets.dart';

import '../../../services/backend_api_service.dart';
import '../data/datasources/sync_queue_local_datasource.dart';
import '../domain/entities/sync_mutation.dart';

/// Drains the offline outbox (SyncQueueLocalDataSource) against the backend.
/// A plain singleton service, not a ChangeNotifier/Provider — nothing in the
/// UI needs to react to its state, it just needs to run in the background.
/// AuthProvider feeds it the current account/token via [updateSession];
/// UserPrefsProvider feeds it mutations via the enqueue* methods.
///
/// Flush triggers: right after enqueueing (fire-and-forget), on app resume
/// (WidgetsBindingObserver, same mechanism PlayerScreen already uses for its
/// own lifecycle handling), and a 30s foreground poll as a catch-all for
/// "connectivity silently came back" — this app's ConnectivityService is a
/// one-shot check today, not a stream, so polling is the lowest-dependency
/// option rather than adding a new connectivity-listening package.
class SyncManager with WidgetsBindingObserver {
  static final SyncManager instance = SyncManager._internal();
  SyncManager._internal();

  final SyncQueueLocalDataSource _queue = SyncQueueLocalDataSource();
  final BackendApiService _api = BackendApiService();

  String? _accountId;
  String? _deviceToken;
  bool _flushing = false;
  Timer? _pollTimer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  /// Not currently called anywhere (this singleton lives for the app's
  /// whole lifetime, same as e.g. DeviceIdService) — provided for symmetry
  /// and so tests can tear it down cleanly.
  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) flush();
  }

  /// Called by AuthProvider whenever the backend connection state changes —
  /// after a successful login (both non-null) and on logout (both null).
  void updateSession({required String? accountId, required String? deviceToken}) {
    _accountId = accountId;
    _deviceToken = deviceToken;
    if (accountId != null && deviceToken != null) flush();
  }

  Future<void> enqueueFavoriteAdd({
    required String accountId,
    required String profileId,
    required String streamId,
    required String streamType,
    required String title,
    required String posterUrl,
    required Map<String, dynamic> rawData,
    required DateTime updatedAt,
  }) async {
    await _queue.enqueue(SyncMutation(
      accountId: accountId,
      profileId: profileId,
      entityType: SyncEntityType.favorite,
      operation: SyncOperation.add,
      payload: {
        'stream_id': streamId,
        'stream_type': streamType,
        'title': title,
        'poster_url': posterUrl,
        'raw_data': rawData,
      },
      clientUpdatedAt: updatedAt,
    ));
    unawaited(flush());
  }

  Future<void> enqueueFavoriteRemove({
    required String accountId,
    required String profileId,
    required String streamId,
    required String streamType,
    required DateTime updatedAt,
  }) async {
    await _queue.enqueue(SyncMutation(
      accountId: accountId,
      profileId: profileId,
      entityType: SyncEntityType.favorite,
      operation: SyncOperation.remove,
      payload: {'stream_id': streamId, 'stream_type': streamType},
      clientUpdatedAt: updatedAt,
    ));
    unawaited(flush());
  }

  Future<void> enqueueHistorySave({
    required String accountId,
    required String profileId,
    required String streamId,
    required String streamType,
    String? episodeId,
    String? seriesId,
    required String title,
    required String posterUrl,
    required int positionSeconds,
    required int durationSeconds,
    required Map<String, dynamic> rawData,
    required DateTime updatedAt,
  }) async {
    await _queue.enqueue(SyncMutation(
      accountId: accountId,
      profileId: profileId,
      entityType: SyncEntityType.history,
      operation: SyncOperation.save,
      payload: {
        'stream_id': streamId,
        'stream_type': streamType,
        'episode_id': episodeId,
        'series_id': seriesId,
        'title': title,
        'poster_url': posterUrl,
        'position_seconds': positionSeconds,
        'duration_seconds': durationSeconds,
        'raw_data': rawData,
      },
      clientUpdatedAt: updatedAt,
    ));
    unawaited(flush());
  }

  Future<void> flush() async {
    final accountId = _accountId;
    final token = _deviceToken;
    if (_flushing || accountId == null || token == null) return;

    _flushing = true;
    try {
      for (final entry in _queue.getAll()) {
        final mutation = entry.value;
        if (mutation.accountId != accountId) continue; // stale entry from a since-logged-out account

        try {
          await _applyMutation(token, mutation);
          await _queue.remove(entry.key);
        } on BackendApiException catch (e) {
          if (!e.retryable) {
            // 4xx business-logic rejection (e.g. profile since deleted) —
            // retrying without something changing would just fail again.
            await _queue.remove(entry.key);
          }
          // else: network/5xx/429 — leave queued, try again next flush.
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _applyMutation(String token, SyncMutation m) async {
    switch (m.entityType) {
      case SyncEntityType.favorite:
        if (m.operation == SyncOperation.add) {
          await _api.addFavorite(
            token,
            profileId: m.profileId,
            streamId: m.payload['stream_id'] as String,
            streamType: m.payload['stream_type'] as String,
            title: m.payload['title'] as String,
            posterUrl: m.payload['poster_url'] as String?,
            rawData: m.payload['raw_data'] as Map<String, dynamic>?,
            updatedAt: m.clientUpdatedAt,
          );
        } else {
          await _api.removeFavorite(
            token,
            profileId: m.profileId,
            streamId: m.payload['stream_id'] as String,
            streamType: m.payload['stream_type'] as String,
          );
        }
        break;
      case SyncEntityType.history:
        await _api.saveHistory(
          token,
          profileId: m.profileId,
          streamId: m.payload['stream_id'] as String,
          streamType: m.payload['stream_type'] as String,
          episodeId: m.payload['episode_id'] as String?,
          seriesId: m.payload['series_id'] as String?,
          title: m.payload['title'] as String,
          posterUrl: m.payload['poster_url'] as String?,
          positionSeconds: m.payload['position_seconds'] as int,
          durationSeconds: m.payload['duration_seconds'] as int,
          rawData: m.payload['raw_data'] as Map<String, dynamic>?,
          updatedAt: m.clientUpdatedAt,
        );
        break;
    }
  }
}
