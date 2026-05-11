enum ExportFormat { youtubeVideo, youtubeShort, instagramReel }

class ExportPreset {
  const ExportPreset({
    required this.format,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.videoBitrateKbps,
    required this.audioBitrateKbps,
  });

  final ExportFormat format;
  final int width;
  final int height;
  final int frameRate;
  final int videoBitrateKbps;
  final int audioBitrateKbps;

  String get label {
    switch (format) {
      case ExportFormat.youtubeVideo:
        return 'YouTube Video';
      case ExportFormat.youtubeShort:
        return 'YouTube Short';
      case ExportFormat.instagramReel:
        return 'Instagram Reel';
    }
  }

  static const List<ExportPreset> defaults = <ExportPreset>[
    ExportPreset(
      format: ExportFormat.youtubeVideo,
      width: 1920,
      height: 1080,
      frameRate: 30,
      videoBitrateKbps: 12000,
      audioBitrateKbps: 320,
    ),
    ExportPreset(
      format: ExportFormat.youtubeShort,
      width: 1080,
      height: 1920,
      frameRate: 30,
      videoBitrateKbps: 10000,
      audioBitrateKbps: 320,
    ),
    ExportPreset(
      format: ExportFormat.instagramReel,
      width: 1080,
      height: 1920,
      frameRate: 30,
      videoBitrateKbps: 9000,
      audioBitrateKbps: 256,
    ),
  ];
}
