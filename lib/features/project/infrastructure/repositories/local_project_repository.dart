import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/project_repository.dart';
import '../datasources/local_project_data_source.dart';

class LocalProjectRepository implements ProjectRepository {
  const LocalProjectRepository(this._dataSource);

  final LocalProjectDataSource _dataSource;

  @override
  Future<Result<Project>> createNew(String projectName) async {
    try {
      final Project project = await _dataSource.createProject(projectName);
      return Success<Project>(project);
    } catch (error) {
      return FailureResult<Project>(
        StorageFailure('Unable to create project', cause: error),
      );
    }
  }

  @override
  Future<Result<Project>> loadFromPath(String path) async {
    try {
      final Project project = await _dataSource.loadProject(path);
      return Success<Project>(project);
    } catch (error) {
      return FailureResult<Project>(
        StorageFailure('Unable to load project', cause: error),
      );
    }
  }

  @override
  Future<Result<void>> saveToPath({
    required Project project,
    required String path,
  }) async {
    try {
      await _dataSource.saveProject(project: project, path: path);
      return const Success<void>(null);
    } catch (error) {
      return FailureResult<void>(
        StorageFailure('Unable to save project', cause: error),
      );
    }
  }
}
