import '../../../../core/result/result.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/project_repository.dart';

class SaveProjectUseCase {
  const SaveProjectUseCase(this._repository);

  final ProjectRepository _repository;

  Future<Result<void>> call({required Project project, required String path}) {
    return _repository.saveToPath(project: project, path: path);
  }
}
