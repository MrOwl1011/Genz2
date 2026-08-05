/// Every timestamp the backend sends back (created_at, updated_at,
/// expires_at, last_seen_at, ...) comes straight from a MySQL DATETIME
/// column via PDO — always formatted like "2026-11-03 07:04:48", always UTC,
/// but with no timezone marker at all. Dart's `DateTime.parse` treats a
/// string with no timezone marker as *local* time, not UTC — parsing one of
/// these directly would silently produce a wrong DateTime shifted by
/// whatever the device's UTC offset is. Appending "Z" (only valid because
/// every caller of this function is known to always be UTC-without-marker)
/// makes Dart parse it correctly, then `.toLocal()` converts it for display.
DateTime parseBackendUtc(String value) {
  return DateTime.parse('${value}Z').toLocal();
}
