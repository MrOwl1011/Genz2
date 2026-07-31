import '../providers/user_prefs_provider.dart' show MediaType;

enum DownloadStatus { downloading, completed, failed }

/// A single downloaded (or downloading) piece of media, scoped to whichever
/// playlist/account was active when it was requested — see
/// [DownloadsProvider] for how that scoping is enforced.
class DownloadItem {
  final String id;
  final String title;
  final String posterUrl;
  final MediaType type;
  final String sourceUrl;
  final Map<String, dynamic> rawData;
  final DateTime createdAt;

  DownloadStatus status;
  String? filePath;
  int totalBytes;
  int downloadedBytes;

  DownloadItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.type,
    required this.sourceUrl,
    required this.rawData,
    required this.createdAt,
    this.status = DownloadStatus.downloading,
    this.filePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
  });

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'posterUrl': posterUrl,
        'type': type.name,
        'sourceUrl': sourceUrl,
        'rawData': rawData,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'filePath': filePath,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      id: json['id'],
      title: json['title'],
      posterUrl: json['posterUrl'],
      type: MediaType.values.firstWhere((e) => e.name == json['type']),
      sourceUrl: json['sourceUrl'] ?? '',
      rawData: Map<String, dynamic>.from(json['rawData'] ?? {}),
      createdAt: DateTime.parse(json['createdAt']),
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.failed,
      ),
      filePath: json['filePath'],
      totalBytes: json['totalBytes'] ?? 0,
      downloadedBytes: json['downloadedBytes'] ?? 0,
    );
  }
}
