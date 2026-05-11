import '../../domain/entities/project.dart';

class ProjectState {
  const ProjectState({
    this.currentProject,
    this.isLoading = false,
    this.errorMessage,
    this.projectFilePath,
  });

  final Project? currentProject;
  final bool isLoading;
  final String? errorMessage;
  final String? projectFilePath;

  ProjectState copyWith({
    Project? currentProject,
    bool? isLoading,
    String? errorMessage,
    String? projectFilePath,
    bool clearProjectFilePath = false,
  }) {
    return ProjectState(
      currentProject: currentProject ?? this.currentProject,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      projectFilePath: clearProjectFilePath
          ? null
          : (projectFilePath ?? this.projectFilePath),
    );
  }
}
