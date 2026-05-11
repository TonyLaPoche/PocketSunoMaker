import '../../domain/entities/project.dart';
import '../../domain/entities/track.dart';

class LocalProjectDataSource {
  const LocalProjectDataSource();

  Future<Project> createProject(String projectName) async {
    // TODO: brancher la persistence JSON .psm.
    return Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: projectName,
      fps: 30,
      canvasWidth: 1920,
      canvasHeight: 1080,
      durationMs: 0,
      tracks: const <Track>[],
    );
  }

  Future<Project> loadProject(String path) async {
    throw UnimplementedError('Load project not implemented for path: $path');
  }

  Future<void> saveProject({
    required Project project,
    required String path,
  }) async {
    throw UnimplementedError('Save project not implemented for path: $path');
  }
}
