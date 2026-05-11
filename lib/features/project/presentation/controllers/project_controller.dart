import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../application/usecases/create_project_use_case.dart';
import '../../domain/entities/project.dart';
import '../../infrastructure/datasources/local_project_data_source.dart';
import '../../infrastructure/repositories/local_project_repository.dart';
import 'project_state.dart';

final Provider<CreateProjectUseCase> createProjectUseCaseProvider =
    Provider<CreateProjectUseCase>((Ref ref) {
      final LocalProjectRepository repository = LocalProjectRepository(
        const LocalProjectDataSource(),
      );
      return CreateProjectUseCase(repository);
    });

final NotifierProvider<ProjectController, ProjectState>
projectControllerProvider = NotifierProvider<ProjectController, ProjectState>(
  ProjectController.new,
);

class ProjectController extends Notifier<ProjectState> {
  late final CreateProjectUseCase _createProjectUseCase;

  @override
  ProjectState build() {
    _createProjectUseCase = ref.read(createProjectUseCaseProvider);
    return const ProjectState();
  }

  Future<void> createNewProject() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final Result<Project> result = await _createProjectUseCase(
      'PocketSunoMaker Project',
    );

    if (result case Success<Project>(:final Project value)) {
      state = state.copyWith(
        currentProject: value,
        isLoading: false,
        errorMessage: null,
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      errorMessage: 'Impossible de creer un nouveau projet.',
    );
  }
}
