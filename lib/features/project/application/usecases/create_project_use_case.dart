import '../../../../core/result/result.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/project_repository.dart';

class CreateProjectUseCase {
  const CreateProjectUseCase(this._repository);

  final ProjectRepository _repository;

  Future<Result<Project>> call(String projectName) {
    return _repository.createNew(projectName);
  }
}
