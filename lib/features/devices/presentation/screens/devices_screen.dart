import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../services/backend_api_service.dart';
import '../../../../theme/app_colors.dart';
import '../../data/datasources/device_remote_datasource.dart';
import '../../domain/entities/device_entity.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _dataSource = DeviceRemoteDataSource();
  List<DeviceEntity> _devices = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _removingDeviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().deviceToken;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Not connected to the sync server right now. Please try again once you have a connection.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final devices = await _dataSource.list(token);
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    } on BackendApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    }
  }

  Future<void> _removeDevice(DeviceEntity device) async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Device?', style: GoogleFonts.outfit(color: colors.ink, fontWeight: FontWeight.bold)),
        content: Text(
          device.isCurrent
              ? 'This is the device you\'re using right now — removing it will log you out here too.'
              : '"${device.deviceName}" will be signed out and will need to log in again to reconnect.',
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Remove', style: GoogleFonts.outfit(color: colors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final token = context.read<AuthProvider>().deviceToken;
    if (token == null) return;

    setState(() => _removingDeviceId = device.deviceId);
    try {
      await _dataSource.remove(token, device.deviceId);
      if (!mounted) return;
      setState(() {
        _devices = _devices.where((d) => d.deviceId != device.deviceId).toList();
        _removingDeviceId = null;
      });

      if (device.isCurrent) {
        await context.read<AuthProvider>().logout();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on BackendApiException catch (e) {
      if (!mounted) return;
      setState(() => _removingDeviceId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: colors.error, content: Text(e.message, style: GoogleFonts.outfit(color: Colors.white))),
      );
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  IconData _platformIcon(String platform) {
    switch (platform) {
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'android':
        return Icons.phone_android_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'windows':
        return Icons.laptop_windows_rounded;
      case 'linux':
        return Icons.computer_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.backgroundGradient,
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.ink),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        'DEVICES',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: colors.ink,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(child: _buildBody(colors)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppColors colors) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.brandPrimary));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, color: colors.ink.withValues(alpha: 0.3), size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.6), fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Text(
          'No devices found.',
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.5)),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: colors.brandPrimary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        physics: const BouncingScrollPhysics(),
        itemCount: _devices.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final device = _devices[index];
          final isRemoving = _removingDeviceId == device.deviceId;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: device.isCurrent ? colors.brandPrimary.withValues(alpha: 0.5) : colors.border,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.brandPrimary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_platformIcon(device.platform), color: colors.brandPrimary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.deviceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(color: colors.ink, fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                          ),
                          if (device.isCurrent) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.brandPrimary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'This device',
                                style: GoogleFonts.outfit(color: colors.brandPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Last seen ${_relativeTime(device.lastSeenAt)}',
                        style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.5), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                isRemoving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colors.error),
                      )
                    : IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: colors.error.withValues(alpha: 0.8)),
                        onPressed: () => _removeDevice(device),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }
}
