import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/media_asset.dart';

class LocalMediaImportDataSource {
  const LocalMediaImportDataSource();

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
      assets.add(
        MediaAsset(
          id: '${stat.modified.millisecondsSinceEpoch}-${p.basename(mediaPath)}',
          path: mediaPath,
          fileName: p.basename(mediaPath),
          kind: _resolveKind(mediaPath),
          sizeBytes: stat.size,
          createdAt: stat.modified,
          durationMs: null,
        ),
      );
    }

    return assets;
  }

  MediaKind _resolveKind(String mediaPath) {
    final String extension = p.extension(mediaPath).replaceFirst('.', '').toLowerCase();
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
}
