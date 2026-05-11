import '../../../../core/result/result.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/project_repository.dart';

class LoadProjectUseCase {
  const LoadProjectUseCase(this._repository);

  final ProjectRepository _repository;

  Future<Result<Project>> call(String path) {
    return _repository.loadFromPath(path);
  }
}
