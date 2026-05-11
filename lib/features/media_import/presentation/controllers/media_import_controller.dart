import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    state = state.copyWith(isLoading: true, errorMessage: null);
    final Result<List<MediaAsset>> result = await _pickMediaAssetsUseCase();
    _mergeResult(result);
  }

  Future<void> importDroppedFiles(List<String> paths) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final Result<List<MediaAsset>> result = await _importDroppedMediaAssetsUseCase(
      paths,
    );
    _mergeResult(result);
  }

  void setDraggingOver(bool value) {
    state = state.copyWith(isDraggingOver: value);
  }

  void _mergeResult(Result<List<MediaAsset>> result) {
    if (result case Success<List<MediaAsset>>(:final List<MediaAsset> value)) {
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

    state = state.copyWith(
      isLoading: false,
      errorMessage: 'Import media impossible.',
    );
  }
}
