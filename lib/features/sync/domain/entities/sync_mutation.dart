import 'dart:convert';

enum SyncEntityType { favorite, history }

enum SyncOperation { add, remove, save }

/// One queued offline write, waiting to reach the backend. Outbox pattern —
/// see SyncQueueLocalDataSource for the Hive-backed queue this lives in, and
/// SyncManager for what drains it.
class SyncMutation {
  final String accountId;
  final String profileId;
  final SyncEntityType entityType;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final DateTime clientUpdatedAt;

  SyncMutation({
    required this.accountId,
    required this.profileId,
    required this.entityType,
    required this.operation,
    required this.payload,
    required this.clientUpdatedAt,
  });

  /// Two mutations with the same coalesce key represent the same underlying
  /// row (e.g. toggling the same favorite off then on again before the
  /// queue ever flushes) — see SyncQueueLocalDataSource.enqueue, which
  /// overwrites rather than appending when this matches an existing entry,
  /// so the queue never grows unbounded and only the latest state per row
  /// ever gets pushed.
  String get coalesceKey =>
      '${entityType.name}:${payload['stream_id']}:${payload['stream_type']}';

  Map<String, dynamic> toHiveMap() => {
        'accountId': accountId,
        'profileId': profileId,
        'entityType': entityType.name,
        'operation': operation.name,
        'payload': payload,
        'clientUpdatedAt': clientUpdatedAt.toUtc().toIso8601String(),
      };

  factory SyncMutation.fromHiveMap(Map<String, dynamic> map) {
    return SyncMutation(
      accountId: map['accountId'] as String,
      profileId: map['profileId'] as String,
      entityType: SyncEntityType.values.firstWhere((e) => e.name == map['entityType']),
      operation: SyncOperation.values.firstWhere((e) => e.name == map['operation']),
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      clientUpdatedAt: DateTime.parse(map['clientUpdatedAt'] as String),
    );
  }

  /// Queue entries are stored in Hive as a JSON-encoded string, not a raw
  /// Hive Map — [payload] can itself embed arbitrary nested Xtream rawData,
  /// same reasoning as HiveBoxes.favoritesBox's doc comment (native Hive Map
  /// storage of that shape hit real silent write failures in practice).
  String toJsonString() => jsonEncode(toHiveMap());

  factory SyncMutation.fromJsonString(String raw) =>
      SyncMutation.fromHiveMap(Map<String, dynamic>.from(jsonDecode(raw) as Map));
}
