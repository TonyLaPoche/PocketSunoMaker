import '../../../../core/result/result.dart';
import '../../domain/entities/media_asset.dart';
import '../../domain/repositories/media_import_repository.dart';

class PickMediaAssetsUseCase {
  const PickMediaAssetsUseCase(this._repository);

  final MediaImportRepository _repository;

  Future<Result<List<MediaAsset>>> call() {
    return _repository.pickMediaAssets();
  }
}
