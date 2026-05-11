import '../../domain/entities/project.dart';

class ProjectState {
  const ProjectState({
    this.currentProject,
    this.isLoading = false,
    this.errorMessage,
  });

  final Project? currentProject;
  final bool isLoading;
  final String? errorMessage;

  ProjectState copyWith({
    Project? currentProject,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ProjectState(
      currentProject: currentProject ?? this.currentProject,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}
