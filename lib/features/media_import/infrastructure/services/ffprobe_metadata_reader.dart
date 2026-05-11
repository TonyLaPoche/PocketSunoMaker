import 'dart:convert';
import 'dart:io';

class MediaProbeResult {
  const MediaProbeResult({
    this.durationMs,
    this.videoWidth,
    this.videoHeight,
    this.frameRate,
    this.codec,
  });

  final int? durationMs;
  final int? videoWidth;
  final int? videoHeight;
  final double? frameRate;
  final String? codec;
}

class FfprobeMetadataReader {
  const FfprobeMetadataReader();

  Future<MediaProbeResult> read(String mediaPath) async {
    final ProcessResult result =
        await Process.run('ffprobe', <String>[
          '-v',
          'error',
          '-print_format',
          'json',
          '-show_streams',
          '-show_format',
          mediaPath,
        ]).timeout(
          const Duration(seconds: 6),
          onTimeout: () => ProcessResult(0, -1, '', 'ffprobe timeout'),
        );

    if (result.exitCode != 0) {
      return const MediaProbeResult();
    }

    final Object? decoded = jsonDecode(result.stdout as String);
    if (decoded is! Map<String, dynamic>) {
      return const MediaProbeResult();
    }

    final Map<String, dynamic>? format =
        decoded['format'] as Map<String, dynamic>?;
    final List<dynamic> streams =
        (decoded['streams'] as List<dynamic>? ?? <dynamic>[]);
    final Map<String, dynamic>? videoStream = streams
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (Map<String, dynamic>? stream) => stream?['codec_type'] == 'video',
          orElse: () => null,
        );
    final Map<String, dynamic>? audioStream = streams
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (Map<String, dynamic>? stream) => stream?['codec_type'] == 'audio',
          orElse: () => null,
        );

    final int? durationMs =
        _parseDurationMs(format?['duration']) ??
        _parseDurationMs(videoStream?['duration']) ??
        _parseDurationMs(audioStream?['duration']);
    final int? width = _parseInt(videoStream?['width']);
    final int? height = _parseInt(videoStream?['height']);
    final double? frameRate = _parseFraction(
      videoStream?['r_frame_rate'] as String?,
    );
    final String? codec =
        (videoStream?['codec_name'] ?? audioStream?['codec_name']) as String?;

    return MediaProbeResult(
      durationMs: durationMs,
      videoWidth: width,
      videoHeight: height,
      frameRate: frameRate,
      codec: codec,
    );
  }

  int? _parseDurationMs(Object? secondsAsValue) {
    if (secondsAsValue == null) {
      return null;
    }
    final double? value = switch (secondsAsValue) {
      String() => double.tryParse(secondsAsValue),
      num() => secondsAsValue.toDouble(),
      _ => null,
    };
    if (value == null) {
      return null;
    }
    return (value * 1000).round();
  }

  int? _parseInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  double? _parseFraction(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (!value.contains('/')) {
      return double.tryParse(value);
    }
    final List<String> parts = value.split('/');
    if (parts.length != 2) {
      return null;
    }
    final double? numerator = double.tryParse(parts.first);
    final double? denominator = double.tryParse(parts.last);
    if (numerator == null || denominator == null || denominator == 0) {
      return null;
    }
    return numerator / denominator;
  }
}
