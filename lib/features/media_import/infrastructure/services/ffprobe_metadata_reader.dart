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
    try {
      final String ffprobe = _resolveFfprobeExecutable();
      final ProcessResult result =
          await Process.run(ffprobe, <String>[
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

      final String stdoutRaw = '${result.stdout ?? ''}'.trim();
      if (stdoutRaw.isEmpty) {
        return const MediaProbeResult();
      }

      final Object? decoded = jsonDecode(stdoutRaw);
      if (decoded is! Map<String, dynamic>) {
        return const MediaProbeResult();
      }

      final Map<String, dynamic>? format =
          decoded['format'] is Map<String, dynamic>
              ? decoded['format'] as Map<String, dynamic>
              : null;
      final List<dynamic> streamsRaw =
          decoded['streams'] is List<dynamic>
              ? decoded['streams'] as List<dynamic>
              : <dynamic>[];

      Map<String, dynamic>? videoStream;
      Map<String, dynamic>? audioStream;
      for (final dynamic raw in streamsRaw) {
        if (raw is! Map<String, dynamic>) {
          continue;
        }
        final Object? ctype = raw['codec_type'];
        if (ctype != 'video' && ctype != 'audio') {
          continue;
        }
        if (ctype == 'video' && videoStream == null) {
          videoStream = raw;
        } else if (ctype == 'audio' && audioStream == null) {
          audioStream = raw;
        }
      }

      final int? durationMs =
          _parseDurationMs(format?['duration']) ??
          _parseDurationMs(videoStream?['duration']) ??
          _parseDurationMs(audioStream?['duration']);
      final int? width = _parseInt(videoStream?['width']);
      final int? height = _parseInt(videoStream?['height']);
      final double? frameRate = _parseFraction(
        videoStream?['r_frame_rate'],
      );
      final String? codec = _stringField(
        videoStream?['codec_name'] ?? audioStream?['codec_name'],
      );

      return MediaProbeResult(
        durationMs: durationMs,
        videoWidth: width,
        videoHeight: height,
        frameRate: frameRate,
        codec: codec,
      );
    } on Object {
      return const MediaProbeResult();
    }
  }

  String _resolveFfprobeExecutable() {
    const List<String> preferredPaths = <String>[
      '/opt/homebrew/opt/ffmpeg-full/bin/ffprobe',
      '/usr/local/opt/ffmpeg-full/bin/ffprobe',
      '/opt/homebrew/bin/ffprobe',
      '/usr/local/bin/ffprobe',
    ];
    for (final String path in preferredPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return 'ffprobe';
  }

  String? _stringField(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return value.toString();
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

  double? _parseFraction(Object? raw) {
    if (raw == null) {
      return null;
    }
    final String value = raw is String ? raw : raw.toString();
    if (value.isEmpty) {
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
