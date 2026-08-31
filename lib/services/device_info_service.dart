import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Resolves a human-readable device model name (e.g. "iPhone 13 Pro",
/// "samsung SM-S911B") for the admin panel's device list — the app used to
/// send a flat platform label ("iPhone/iPad", "Android Device") with no way
/// to tell which actual device a session belonged to.
class DeviceInfoService {
  DeviceInfoService._();

  static Future<String> getDeviceModelName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) return 'Web Browser';

      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final identifier = info.utsname.machine;
        return _iosModelNames[identifier] ?? identifier;
      }

      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final manufacturer = info.manufacturer.trim();
        final model = info.model.trim();
        // A handful of common Samsung flagship codes mapped to their
        // marketing name — Android model codes are far too fragmented
        // across manufacturers to maintain a comprehensive table the way
        // Apple's small, fixed identifier set allows below, so everything
        // else just shows "manufacturer model" (still a real, accurate,
        // lookup-able identifier — just not a marketing name).
        final friendly = _androidModelNames[model];
        if (friendly != null) return friendly;
        if (manufacturer.isEmpty) return model;
        return '$manufacturer $model';
      }

      if (Platform.isMacOS) return 'Mac';
      if (Platform.isWindows) return 'Windows PC';
      if (Platform.isLinux) return 'Linux PC';
      return 'Device';
    } catch (_) {
      // device_info_plus failing is not worth ever blocking login over —
      // same non-fatal philosophy as the rest of the backend-sync path
      // this feeds into (see AuthProvider._syncBackendAndProfiles).
      if (Platform.isIOS) return 'iPhone/iPad';
      if (Platform.isAndroid) return 'Android Device';
      return 'Device';
    }
  }

  // Apple's utsname.machine identifiers — a small, fixed, slowly-growing
  // set (unlike Android's model codes), so a maintained table here stays
  // practical. Falls back to the raw identifier (e.g. "iPhone99,1") for
  // any future model released after this list was last updated, rather
  // than a generic "iPhone/iPad" that loses the information entirely.
  static const Map<String, String> _iosModelNames = {
    // iPhone
    'iPhone8,1': 'iPhone 6s',
    'iPhone8,2': 'iPhone 6s Plus',
    'iPhone8,4': 'iPhone SE (1st gen)',
    'iPhone9,1': 'iPhone 7',
    'iPhone9,3': 'iPhone 7',
    'iPhone9,2': 'iPhone 7 Plus',
    'iPhone9,4': 'iPhone 7 Plus',
    'iPhone10,1': 'iPhone 8',
    'iPhone10,4': 'iPhone 8',
    'iPhone10,2': 'iPhone 8 Plus',
    'iPhone10,5': 'iPhone 8 Plus',
    'iPhone10,3': 'iPhone X',
    'iPhone10,6': 'iPhone X',
    'iPhone11,2': 'iPhone XS',
    'iPhone11,4': 'iPhone XS Max',
    'iPhone11,6': 'iPhone XS Max',
    'iPhone11,8': 'iPhone XR',
    'iPhone12,1': 'iPhone 11',
    'iPhone12,3': 'iPhone 11 Pro',
    'iPhone12,5': 'iPhone 11 Pro Max',
    'iPhone12,8': 'iPhone SE (2nd gen)',
    'iPhone13,1': 'iPhone 12 mini',
    'iPhone13,2': 'iPhone 12',
    'iPhone13,3': 'iPhone 12 Pro',
    'iPhone13,4': 'iPhone 12 Pro Max',
    'iPhone14,2': 'iPhone 13 Pro',
    'iPhone14,3': 'iPhone 13 Pro Max',
    'iPhone14,4': 'iPhone 13 mini',
    'iPhone14,5': 'iPhone 13',
    'iPhone14,6': 'iPhone SE (3rd gen)',
    'iPhone14,7': 'iPhone 14',
    'iPhone14,8': 'iPhone 14 Plus',
    'iPhone15,2': 'iPhone 14 Pro',
    'iPhone15,3': 'iPhone 14 Pro Max',
    'iPhone15,4': 'iPhone 15',
    'iPhone15,5': 'iPhone 15 Plus',
    'iPhone16,1': 'iPhone 15 Pro',
    'iPhone16,2': 'iPhone 15 Pro Max',
    'iPhone17,1': 'iPhone 16 Pro',
    'iPhone17,2': 'iPhone 16 Pro Max',
    'iPhone17,3': 'iPhone 16',
    'iPhone17,4': 'iPhone 16 Plus',
    'iPhone17,5': 'iPhone 16e',
    // iPad
    'iPad11,1': 'iPad mini (5th gen)',
    'iPad11,2': 'iPad mini (5th gen)',
    'iPad11,3': 'iPad Air (3rd gen)',
    'iPad11,4': 'iPad Air (3rd gen)',
    'iPad11,6': 'iPad (8th gen)',
    'iPad11,7': 'iPad (8th gen)',
    'iPad12,1': 'iPad (9th gen)',
    'iPad12,2': 'iPad (9th gen)',
    'iPad13,1': 'iPad Air (4th gen)',
    'iPad13,2': 'iPad Air (4th gen)',
    'iPad13,4': 'iPad Pro 11-inch (5th gen)',
    'iPad13,5': 'iPad Pro 11-inch (5th gen)',
    'iPad13,6': 'iPad Pro 11-inch (5th gen)',
    'iPad13,7': 'iPad Pro 11-inch (5th gen)',
    'iPad13,8': 'iPad Pro 12.9-inch (5th gen)',
    'iPad13,9': 'iPad Pro 12.9-inch (5th gen)',
    'iPad13,10': 'iPad Pro 12.9-inch (5th gen)',
    'iPad13,11': 'iPad Pro 12.9-inch (5th gen)',
    'iPad13,16': 'iPad Air (5th gen)',
    'iPad13,17': 'iPad Air (5th gen)',
    'iPad13,18': 'iPad (10th gen)',
    'iPad13,19': 'iPad (10th gen)',
    'iPad14,1': 'iPad mini (6th gen)',
    'iPad14,2': 'iPad mini (6th gen)',
    'iPad14,3': 'iPad Pro 11-inch (4th gen)',
    'iPad14,4': 'iPad Pro 11-inch (4th gen)',
    'iPad14,5': 'iPad Pro 12.9-inch (6th gen)',
    'iPad14,6': 'iPad Pro 12.9-inch (6th gen)',
    'iPad14,8': 'iPad Air 11-inch (M2)',
    'iPad14,9': 'iPad Air 11-inch (M2)',
    'iPad14,10': 'iPad Air 13-inch (M2)',
    'iPad14,11': 'iPad Air 13-inch (M2)',
    'iPad16,3': 'iPad Pro 11-inch (M4)',
    'iPad16,4': 'iPad Pro 11-inch (M4)',
    'iPad16,5': 'iPad Pro 13-inch (M4)',
    'iPad16,6': 'iPad Pro 13-inch (M4)',
    // Simulator — utsname.machine is the host CPU arch, not a device
    'x86_64': 'iOS Simulator',
    'arm64': 'iOS Simulator',
  };

  // Recent Samsung Galaxy S/Note flagship model codes — the most common
  // "I want the marketing name, not the model number" case in practice.
  static const Map<String, String> _androidModelNames = {
    'SM-S911B': 'Galaxy S23',
    'SM-S916B': 'Galaxy S23+',
    'SM-S918B': 'Galaxy S23 Ultra',
    'SM-S921B': 'Galaxy S24',
    'SM-S926B': 'Galaxy S24+',
    'SM-S928B': 'Galaxy S24 Ultra',
    'SM-S931B': 'Galaxy S25',
    'SM-S936B': 'Galaxy S25+',
    'SM-S938B': 'Galaxy S25 Ultra',
    'SM-N986B': 'Galaxy Note 20 Ultra',
    'SM-F946B': 'Galaxy Z Fold5',
    'SM-F956B': 'Galaxy Z Fold6',
    'SM-F731B': 'Galaxy Z Flip5',
    'SM-F741B': 'Galaxy Z Flip6',
  };
}
