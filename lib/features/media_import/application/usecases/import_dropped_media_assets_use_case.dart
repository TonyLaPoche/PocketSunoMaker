import '../../../../core/result/result.dart';
import '../../domain/entities/media_asset.dart';
import '../../domain/repositories/media_import_repository.dart';

class ImportDroppedMediaAssetsUseCase {
  const ImportDroppedMediaAssetsUseCase(this._repository);

  final MediaImportRepository _repository;

  Future<Result<List<MediaAsset>>> call(List<String> paths) {
    return _repository.importFromPaths(paths);
  }
}
