import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../application/usecases/import_dropped_media_assets_use_case.dart';
import '../../application/usecases/pick_media_assets_use_case.dart';
import '../../domain/entities/media_asset.dart';
import '../../infrastructure/datasources/local_media_import_data_source.dart';
import '../../infrastructure/repositories/local_media_import_repository.dart';
import '../../../project/domain/entities/project.dart';
import 'media_import_state.dart';

final Provider<PickMediaAssetsUseCase> pickMediaAssetsUseCaseProvider =
    Provider<PickMediaAssetsUseCase>((Ref ref) {
      final LocalMediaImportRepository repository = LocalMediaImportRepository(
        const LocalMediaImportDataSource(),
      );
      return PickMediaAssetsUseCase(repository);
    });

final Provider<ImportDroppedMediaAssetsUseCase>
importDroppedMediaAssetsUseCaseProvider =
    Provider<ImportDroppedMediaAssetsUseCase>((Ref ref) {
      final LocalMediaImportRepository repository = LocalMediaImportRepository(
        const LocalMediaImportDataSource(),
      );
      return ImportDroppedMediaAssetsUseCase(repository);
    });

final NotifierProvider<MediaImportController, MediaImportState>
mediaImportControllerProvider =
    NotifierProvider<MediaImportController, MediaImportState>(
      MediaImportController.new,
    );

class MediaImportController extends Notifier<MediaImportState> {
  late final PickMediaAssetsUseCase _pickMediaAssetsUseCase;
  late final ImportDroppedMediaAssetsUseCase _importDroppedMediaAssetsUseCase;

  @override
  MediaImportState build() {
    _pickMediaAssetsUseCase = ref.read(pickMediaAssetsUseCaseProvider);
    _importDroppedMediaAssetsUseCase = ref.read(
      importDroppedMediaAssetsUseCaseProvider,
    );
    return const MediaImportState();
  }

  Future<void> pickMediaFiles() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final Result<List<MediaAsset>> result = await _pickMediaAssetsUseCase()
          .timeout(const Duration(seconds: 20));
      _mergeResult(result, emptyMessage: 'Aucun media selectionne.');
    } on TimeoutException {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Import trop long. Reessaie avec moins de fichiers en une fois.',
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Erreur inattendue pendant l import.',
      );
    }
  }

  Future<void> importDroppedFiles(List<String> paths) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final Result<List<MediaAsset>> result =
          await _importDroppedMediaAssetsUseCase(
            paths,
          ).timeout(const Duration(seconds: 20));
      _mergeResult(result, emptyMessage: 'Aucun fichier exploitable depose.');
    } on TimeoutException {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Import trop long apres depot des fichiers.',
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Erreur inattendue pendant l import.',
      );
    }
  }

  void setDraggingOver(bool value) {
    state = state.copyWith(isDraggingOver: value);
  }

  void removeAssetById(String assetId) {
    final List<MediaAsset> filtered = state.assets
        .where((MediaAsset asset) => asset.id != assetId)
        .toList(growable: false);
    state = state.copyWith(assets: filtered, errorMessage: null);
  }

  void synchronizeFromProject(Project? project) {
    if (project == null) {
      return;
    }
    final Set<String> clipPaths = project.tracks
        .expand((track) => track.clips)
        .map((clip) => clip.assetPath)
        .toSet();
    if (clipPaths.isEmpty) {
      return;
    }
    final Map<String, MediaAsset> byPath = <String, MediaAsset>{
      for (final MediaAsset asset in state.assets) asset.path: asset,
    };
    bool changed = false;
    for (final String path in clipPaths) {
      if (byPath.containsKey(path)) {
        continue;
      }
      byPath[path] = _buildFallbackAsset(path);
      changed = true;
    }
    if (!changed) {
      return;
    }
    state = state.copyWith(
      assets: byPath.values.toList(growable: false),
      errorMessage: null,
    );
  }

  void _mergeResult(
    Result<List<MediaAsset>> result, {
    required String emptyMessage,
  }) {
    if (result case Success<List<MediaAsset>>(:final List<MediaAsset> value)) {
      if (value.isEmpty) {
        state = state.copyWith(isLoading: false, errorMessage: emptyMessage);
        return;
      }
      final Map<String, MediaAsset> deduplicated = <String, MediaAsset>{
        for (final MediaAsset existing in state.assets) existing.path: existing,
      };
      for (final MediaAsset newAsset in value) {
        deduplicated[newAsset.path] = newAsset;
      }
      state = state.copyWith(
        assets: deduplicated.values.toList(growable: false),
        isLoading: false,
        errorMessage: null,
      );
      return;
    }

    final String failureMessage = switch (result) {
      FailureResult<List<MediaAsset>>(:final Object failure) =>
        failure is Failure ? failure.message : failure.toString(),
      _ => 'Import media impossible.',
    };

    state = state.copyWith(isLoading: false, errorMessage: failureMessage);
  }

  MediaAsset _buildFallbackAsset(String mediaPath) {
    final File file = File(mediaPath);
    int sizeBytes = 0;
    DateTime createdAt = DateTime.now();
    try {
      final FileStat stat = file.statSync();
      sizeBytes = stat.size;
      createdAt = stat.modified;
    } on FileSystemException {
      // Keep fallback values for inaccessible paths.
    }
    return MediaAsset(
      id: 'project-ref-$mediaPath',
      path: mediaPath,
      fileName: p.basename(mediaPath),
      kind: _resolveKind(mediaPath),
      sizeBytes: sizeBytes,
      createdAt: createdAt,
    );
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
}
