import '../../../../core/datetime_utils.dart';

/// A device currently logged into this Xtream account, as reported by the
/// backend. Deliberately no local cache/repository for this feature — a
/// device list is only ever meaningful live (a cached one would just show
/// stale sessions), so DevicesScreen talks to BackendApiService directly via
/// DeviceRemoteDataSource rather than going through an offline-first layer
/// like profiles/favorites/history do.
class DeviceEntity {
  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime lastSeenAt;
  final bool isCurrent;

  const DeviceEntity({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.lastSeenAt,
    required this.isCurrent,
  });

  factory DeviceEntity.fromBackendJson(Map<String, dynamic> json) {
    return DeviceEntity(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      platform: json['platform'] as String,
      lastSeenAt: parseBackendUtc(json['last_seen_at'] as String),
      isCurrent: json['is_current'] == true,
    );
  }
}
