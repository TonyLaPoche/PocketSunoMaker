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

  static const List<XTypeGroup> _acceptedTypes = <XTypeGroup>[
    XTypeGroup(
      label: 'Media',
      extensions: <String>[
        'mp4',
        'mov',
        'mkv',
        'webm',
        'mp3',
        'wav',
        'aiff',
        'flac',
        'png',
        'jpg',
        'jpeg',
        'webp',
      ],
    ),
  ];

  Future<List<String>> pickPaths() async {
    final List<XFile> files = await openFiles(
      acceptedTypeGroups: _acceptedTypes,
    );
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
    }

    return assets;
  }

  MediaKind _resolveKind(String mediaPath) {
    final String extension = p
        .extension(mediaPath)
        .replaceFirst('.', '')
        .toLowerCase();
    const Set<String> videoExtensions = <String>{'mp4', 'mov', 'mkv', 'webm'};
    const Set<String> audioExtensions = <String>{'mp3', 'wav', 'aiff', 'flac'};
    const Set<String> imageExtensions = <String>{'png', 'jpg', 'jpeg', 'webp'};

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
}
