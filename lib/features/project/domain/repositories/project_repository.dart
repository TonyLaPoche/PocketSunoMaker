import '../../../../core/result/result.dart';
import '../entities/project.dart';

abstract interface class ProjectRepository {
  Future<Result<Project>> createNew(String projectName);

  Future<Result<Project>> loadFromPath(String path);

  Future<Result<void>> saveToPath({
    required Project project,
    required String path,
  });
}
