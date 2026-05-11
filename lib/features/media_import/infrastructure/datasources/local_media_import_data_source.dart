import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/media_asset.dart';
import '../services/ffprobe_metadata_reader.dart';

class LocalMediaImportDataSource {
  const LocalMediaImportDataSource({
    this.metadataReader = const FfprobeMetadataReader(),
  });

  final FfprobeMetadataReader metadataReader;

  Future<List<String>> pickPaths() async {
    // On laisse volontairement le picker sans filtre strict: cela evite les
    // soucis de compatibilite selon l'OS et laisse l'utilisateur choisir librement.
    final List<XFile> files = await openFiles();
    return files.map((XFile file) => file.path).toList(growable: false);
  }

  Future<List<MediaAsset>> buildAssetsFromPaths(List<String> paths) async {
    final List<MediaAsset> assets = <MediaAsset>[];

    for (final String mediaPath in paths) {
      final File file = File(mediaPath);
      if (!await file.exists()) {
        continue;
      }

      final FileStat stat = await file.stat();
      final MediaKind kind = _resolveKind(mediaPath);
      final MediaProbeResult probeResult = await _safeReadMetadata(mediaPath);
      final int? durationMs =
          probeResult.durationMs ??
          (kind == MediaKind.audio
              ? await _safeReadAudioDurationMs(mediaPath)
              : null);
      assets.add(
        MediaAsset(
          id: '${stat.modified.millisecondsSinceEpoch}-${p.basename(mediaPath)}',
          path: mediaPath,
          fileName: p.basename(mediaPath),
          kind: kind,
          sizeBytes: stat.size,
          createdAt: stat.modified,
          durationMs: durationMs,
          videoWidth: probeResult.videoWidth,
          videoHeight: probeResult.videoHeight,
          frameRate: probeResult.frameRate,
          codec: probeResult.codec,
        ),
      );
    }

    return assets;
  }

  MediaKind _resolveKind(String mediaPath) {
    final String extension = p
        .extension(mediaPath)
        .replaceFirst('.', '')
        .toLowerCase();
    const Set<String> videoExtensions = <String>{
      'mp4',
      'm4v',
      'mov',
      'mkv',
      'avi',
      'webm',
    };
    const Set<String> audioExtensions = <String>{
      'mp3',
      'm4a',
      'aac',
      'ogg',
      'opus',
      'wav',
      'aiff',
      'flac',
    };
    const Set<String> imageExtensions = <String>{
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'bmp',
      'tif',
      'tiff',
    };

    if (videoExtensions.contains(extension)) {
      return MediaKind.video;
    }
    if (audioExtensions.contains(extension)) {
      return MediaKind.audio;
    }
    if (imageExtensions.contains(extension)) {
      return MediaKind.image;
    }
    return MediaKind.unknown;
  }

  Future<MediaProbeResult> _safeReadMetadata(String mediaPath) async {
    try {
      return await metadataReader.read(mediaPath);
    } catch (_) {
      return const MediaProbeResult();
    }
  }

  Future<int?> _safeReadAudioDurationMs(String mediaPath) async {
    final AudioPlayer player = AudioPlayer();
    try {
      await player.setFilePath(mediaPath).timeout(const Duration(seconds: 4));
      return player.duration?.inMilliseconds;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }
}
