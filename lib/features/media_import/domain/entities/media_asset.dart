enum MediaKind { video, audio, image, unknown }

class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.path,
    required this.fileName,
    required this.kind,
    required this.sizeBytes,
    required this.createdAt,
    this.durationMs,
  });

  final String id;
  final String path;
  final String fileName;
  final MediaKind kind;
  final int sizeBytes;
  final DateTime createdAt;
  final int? durationMs;

  String get kindLabel {
    switch (kind) {
      case MediaKind.video:
        return 'Video';
      case MediaKind.audio:
        return 'Audio';
      case MediaKind.image:
        return 'Image';
      case MediaKind.unknown:
        return 'Unknown';
    }
  }
}
