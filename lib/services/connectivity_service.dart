import 'dart:io';

/// Minimal one-shot internet-reachability check — no external plugin
/// dependency required. Used once at app startup to decide whether to show
/// the "no internet" gate; this is a point-in-time check, not a continuous
/// connectivity listener.
class ConnectivityService {
  ConnectivityService._();

  // Tried in order; the first that resolves counts as "online". Multiple
  // hosts guard against one of them being regionally blocked or transiently
  // down and being mistaken for the device being offline.
  static const List<String> _probeHosts = ['google.com', 'cloudflare.com', 'apple.com'];

  static Future<bool> hasConnection({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    for (final host in _probeHosts) {
      try {
        final result = await InternetAddress.lookup(host).timeout(timeout);
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {
        // Try the next host.
      }
    }
    return false;
  }
}
