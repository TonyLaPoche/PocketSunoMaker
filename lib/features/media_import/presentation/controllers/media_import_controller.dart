import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../application/usecases/import_dropped_media_assets_use_case.dart';
import '../../application/usecases/pick_media_assets_use_case.dart';
import '../../domain/entities/media_asset.dart';
import '../../infrastructure/datasources/local_media_import_data_source.dart';
import '../../infrastructure/repositories/local_media_import_repository.dart';
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
    _log('pickMediaFiles start');
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final Result<List<MediaAsset>> result = await _pickMediaAssetsUseCase()
          .timeout(const Duration(seconds: 20));
      _mergeResult(result, emptyMessage: 'Aucun media selectionne.');
    } on TimeoutException catch (error, stackTrace) {
      _log('pickMediaFiles timeout: $error');
      _log(stackTrace.toString());
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Import trop long. Reessaie avec moins de fichiers en une fois.',
      );
    } catch (error, stackTrace) {
      _log('pickMediaFiles unexpected error: $error');
      _log(stackTrace.toString());
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Erreur inattendue pendant l import.',
      );
    }
    _log(
      'pickMediaFiles end, loading=${state.isLoading}, assets=${state.assets.length}',
    );
  }

  Future<void> importDroppedFiles(List<String> paths) async {
    _log('importDroppedFiles start, paths=${paths.length}');
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final Result<List<MediaAsset>> result =
          await _importDroppedMediaAssetsUseCase(
            paths,
          ).timeout(const Duration(seconds: 20));
      _mergeResult(result, emptyMessage: 'Aucun fichier exploitable depose.');
    } on TimeoutException {
      _log('importDroppedFiles timeout');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Import trop long apres depot des fichiers.',
      );
    } catch (error, stackTrace) {
      _log('importDroppedFiles unexpected error: $error');
      _log(stackTrace.toString());
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Erreur inattendue pendant l import.',
      );
    }
    _log(
      'importDroppedFiles end, loading=${state.isLoading}, assets=${state.assets.length}',
    );
  }

  void setDraggingOver(bool value) {
    state = state.copyWith(isDraggingOver: value);
  }

  void _mergeResult(
    Result<List<MediaAsset>> result, {
    required String emptyMessage,
  }) {
    if (result case Success<List<MediaAsset>>(:final List<MediaAsset> value)) {
      if (value.isEmpty) {
        state = state.copyWith(isLoading: false, errorMessage: emptyMessage);
        _log('mergeResult success but empty');
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
      _log(
        'mergeResult success, imported=${value.length}, total=${state.assets.length}',
      );
      return;
    }

    final String failureMessage = switch (result) {
      FailureResult<List<MediaAsset>>(:final Object failure) =>
        failure is Failure ? failure.message : failure.toString(),
      _ => 'Import media impossible.',
    };

    state = state.copyWith(isLoading: false, errorMessage: failureMessage);
    _log('mergeResult failure: $failureMessage');
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[MediaImportController] $message');
  }
}
