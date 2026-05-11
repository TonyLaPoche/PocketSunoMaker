import '../../../../core/result/result.dart';
import '../entities/media_asset.dart';

abstract interface class MediaImportRepository {
  Future<Result<List<MediaAsset>>> pickMediaAssets();

  Future<Result<List<MediaAsset>>> importFromPaths(List<String> paths);
}
