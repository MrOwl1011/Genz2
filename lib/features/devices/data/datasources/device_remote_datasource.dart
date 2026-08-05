import '../../../../services/backend_api_service.dart';
import '../../domain/entities/device_entity.dart';

class DeviceRemoteDataSource {
  final BackendApiService _api;

  DeviceRemoteDataSource([BackendApiService? api]) : _api = api ?? BackendApiService();

  Future<List<DeviceEntity>> list(String token) async {
    final rows = await _api.listDevices(token);
    return rows.map(DeviceEntity.fromBackendJson).toList();
  }

  Future<void> remove(String token, String deviceId) async {
    await _api.removeDevice(token, deviceId);
  }
}
