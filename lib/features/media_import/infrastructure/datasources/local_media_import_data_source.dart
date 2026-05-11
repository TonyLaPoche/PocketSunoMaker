import 'dart:io';

import 'package:file_selector/file_selector.dart';
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
    _log('Opening native file picker');
    final List<XFile> files = await openFiles();
    final List<String> paths = files
        .map((XFile file) => file.path)
        .toList(growable: false);
    _log('Picker returned ${paths.length} file(s)');
    return paths;
  }

  Future<List<MediaAsset>> buildAssetsFromPaths(List<String> paths) async {
    _log('Building assets from ${paths.length} path(s)');
    final List<MediaAsset> assets = <MediaAsset>[];

    for (final String mediaPath in paths) {
      final File file = File(mediaPath);
      if (!await file.exists()) {
        _log('File does not exist, skip: $mediaPath');
        continue;
      }

      final FileStat stat = await file.stat();
      final MediaProbeResult probeResult = await _safeReadMetadata(mediaPath);
      assets.add(
        MediaAsset(
          id: '${stat.modified.millisecondsSinceEpoch}-${p.basename(mediaPath)}',
          path: mediaPath,
          fileName: p.basename(mediaPath),
          kind: _resolveKind(mediaPath),
          sizeBytes: stat.size,
          createdAt: stat.modified,
          durationMs: probeResult.durationMs,
          videoWidth: probeResult.videoWidth,
          videoHeight: probeResult.videoHeight,
          frameRate: probeResult.frameRate,
          codec: probeResult.codec,
        ),
      );
      _log(
        'Asset built: ${p.basename(mediaPath)} (durationMs=${probeResult.durationMs})',
      );
    }

    _log('buildAssetsFromPaths done, assets=${assets.length}');
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
    } catch (error) {
      _log('Metadata read error for $mediaPath: $error');
      return const MediaProbeResult();
    }
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[LocalMediaImportDataSource] $message');
  }
}
