import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/media_asset.dart';
import '../../domain/repositories/media_import_repository.dart';
import '../datasources/local_media_import_data_source.dart';

class LocalMediaImportRepository implements MediaImportRepository {
  const LocalMediaImportRepository(this._dataSource);

  final LocalMediaImportDataSource _dataSource;

  @override
  Future<Result<List<MediaAsset>>> pickMediaAssets() async {
    try {
      final List<String> paths = await _dataSource.pickPaths();
      final List<MediaAsset> assets = await _dataSource.buildAssetsFromPaths(paths);
      return Success<List<MediaAsset>>(assets);
    } catch (error) {
      return FailureResult<List<MediaAsset>>(
        StorageFailure('Unable to pick media files', cause: error),
      );
    }
  }

  @override
  Future<Result<List<MediaAsset>>> importFromPaths(List<String> paths) async {
    try {
      final List<MediaAsset> assets = await _dataSource.buildAssetsFromPaths(paths);
      return Success<List<MediaAsset>>(assets);
    } catch (error) {
      return FailureResult<List<MediaAsset>>(
        StorageFailure('Unable to import dropped files', cause: error),
      );
    }
  }
}
