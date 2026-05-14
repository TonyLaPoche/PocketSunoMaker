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
    this.videoWidth,
    this.videoHeight,
    this.frameRate,
    this.codec,
  });

  final String id;
  final String path;
  final String fileName;
  final MediaKind kind;
  final int sizeBytes;
  final DateTime createdAt;
  final int? durationMs;
  final int? videoWidth;
  final int? videoHeight;
  final double? frameRate;
  final String? codec;

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

  String get technicalSummary {
    final List<String> parts = <String>[];

    if (durationMs != null) {
      final int totalSeconds = durationMs! ~/ 1000;
      final int minutes = totalSeconds ~/ 60;
      final int seconds = totalSeconds % 60;
      parts.add(
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
      );
    }
    if (videoWidth != null && videoHeight != null) {
      parts.add('${videoWidth}x$videoHeight');
    }
    if (frameRate != null && frameRate!.isFinite) {
      parts.add('${frameRate!.toStringAsFixed(2)} fps');
    }
    if (codec != null && codec!.isNotEmpty) {
      parts.add(codec!);
    }

    if (parts.isEmpty) {
      return 'Metadata en attente';
    }

    return parts.join(' - ');
  }
}
