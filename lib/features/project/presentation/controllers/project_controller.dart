import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../../../core/result/result.dart';
import '../../../media_import/domain/entities/media_asset.dart';
import '../../application/usecases/create_project_use_case.dart';
import '../../application/usecases/load_project_use_case.dart';
import '../../application/usecases/save_project_use_case.dart';
import '../../domain/entities/clip.dart';
import '../../domain/entities/project.dart';
import '../../domain/entities/track.dart';
import '../../infrastructure/datasources/local_project_data_source.dart';
import '../../infrastructure/repositories/local_project_repository.dart';
import 'project_state.dart';

final Provider<LocalProjectRepository> projectRepositoryProvider =
    Provider<LocalProjectRepository>((Ref ref) {
      return LocalProjectRepository(const LocalProjectDataSource());
    });

final Provider<CreateProjectUseCase> createProjectUseCaseProvider =
    Provider<CreateProjectUseCase>((Ref ref) {
      return CreateProjectUseCase(ref.read(projectRepositoryProvider));
    });

final Provider<LoadProjectUseCase> loadProjectUseCaseProvider =
    Provider<LoadProjectUseCase>((Ref ref) {
      return LoadProjectUseCase(ref.read(projectRepositoryProvider));
    });

final Provider<SaveProjectUseCase> saveProjectUseCaseProvider =
    Provider<SaveProjectUseCase>((Ref ref) {
      return SaveProjectUseCase(ref.read(projectRepositoryProvider));
    });

final NotifierProvider<ProjectController, ProjectState>
projectControllerProvider = NotifierProvider<ProjectController, ProjectState>(
  ProjectController.new,
);

class ProjectController extends Notifier<ProjectState> {
  late final CreateProjectUseCase _createProjectUseCase;
  late final LoadProjectUseCase _loadProjectUseCase;
  late final SaveProjectUseCase _saveProjectUseCase;

  static const XTypeGroup _projectTypeGroup = XTypeGroup(
    label: 'PocketSunoMaker Project',
    extensions: <String>['psm'],
  );

  @override
  ProjectState build() {
    _createProjectUseCase = ref.read(createProjectUseCaseProvider);
    _loadProjectUseCase = ref.read(loadProjectUseCaseProvider);
    _saveProjectUseCase = ref.read(saveProjectUseCaseProvider);
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
        clearProjectFilePath: true,
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      errorMessage: 'Impossible de creer un nouveau projet.',
    );
  }

  Future<void> saveCurrentProject() async {
    final Project? currentProject = state.currentProject;
    if (currentProject == null) {
      state = state.copyWith(errorMessage: 'Aucun projet a sauvegarder.');
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    final String defaultName = '${_sanitizeFileName(currentProject.name)}.psm';
    final FileSaveLocation? destination = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[_projectTypeGroup],
      suggestedName: defaultName,
    );

    if (destination == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    final Result<void> result = await _saveProjectUseCase(
      project: currentProject,
      path: destination.path,
    );

    if (result.isSuccess) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: null,
        projectFilePath: destination.path,
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      errorMessage: 'Impossible de sauvegarder le projet.',
    );
  }

  Future<void> loadProjectFromDisk() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final XFile? selectedFile = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_projectTypeGroup],
    );

    if (selectedFile == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    final Result<Project> result = await _loadProjectUseCase(selectedFile.path);

    if (result case Success<Project>(:final Project value)) {
      state = state.copyWith(
        currentProject: value,
        isLoading: false,
        errorMessage: null,
        projectFilePath: selectedFile.path,
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      errorMessage: 'Impossible de charger le projet.',
    );
  }

  void addAssetToTimeline(MediaAsset asset) {
    final Project? project = state.currentProject;
    if (project == null) {
      state = state.copyWith(
        errorMessage: 'Cree un projet avant d ajouter des clips.',
      );
      return;
    }

    final TrackType targetType = asset.kind == MediaKind.audio
        ? TrackType.audio
        : TrackType.video;

    final List<Track> tracks = List<Track>.from(project.tracks);
    final int existingTrackIndex = tracks.indexWhere(
      (Track track) => track.type == targetType,
    );

    final Track targetTrack;
    if (existingTrackIndex == -1) {
      targetTrack = Track(
        id: '${targetType.name}-track-${DateTime.now().millisecondsSinceEpoch}',
        type: targetType,
        index: tracks.length,
        clips: const <Clip>[],
      );
      tracks.add(targetTrack);
    } else {
      targetTrack = tracks[existingTrackIndex];
    }

    final int timelineStartMs = _computeTrackEndMs(targetTrack);
    final int durationMs = _clipDurationForAsset(asset);
    final Clip newClip = Clip(
      id: 'clip-${DateTime.now().microsecondsSinceEpoch}',
      assetPath: asset.path,
      timelineStartMs: timelineStartMs,
      sourceInMs: 0,
      sourceOutMs: durationMs,
    );

    final Track updatedTrack = targetTrack.copyWith(
      clips: <Clip>[...targetTrack.clips, newClip],
    );

    if (existingTrackIndex == -1) {
      tracks[tracks.length - 1] = updatedTrack;
    } else {
      tracks[existingTrackIndex] = updatedTrack;
    }

    final int projectDurationMs = _computeProjectDurationMs(tracks);
    final Project updatedProject = project.copyWith(
      tracks: tracks,
      durationMs: projectDurationMs,
    );

    state = state.copyWith(currentProject: updatedProject, errorMessage: null);
  }

  String _sanitizeFileName(String source) {
    final String noExtension = p.basenameWithoutExtension(source.trim());
    final String safe = noExtension.replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]'), '');
    final String compact = safe.replaceAll(RegExp(r'\s+'), '_');
    if (compact.isEmpty) {
      return 'PocketSunoMaker_Project';
    }
    return compact;
  }

  int _computeTrackEndMs(Track track) {
    if (track.clips.isEmpty) {
      return 0;
    }
    return track.clips
        .map((Clip clip) => clip.timelineStartMs + clip.durationMs)
        .reduce((int max, int value) => value > max ? value : max);
  }

  int _computeProjectDurationMs(List<Track> tracks) {
    if (tracks.isEmpty) {
      return 0;
    }
    final List<int> clipEnds = tracks
        .expand((Track track) => track.clips)
        .map((Clip clip) => clip.timelineStartMs + clip.durationMs)
        .toList(growable: false);
    if (clipEnds.isEmpty) {
      return 0;
    }
    return clipEnds.reduce((int max, int value) => value > max ? value : max);
  }

  int _clipDurationForAsset(MediaAsset asset) {
    if (asset.durationMs != null && asset.durationMs! > 0) {
      return asset.durationMs!;
    }
    if (asset.kind == MediaKind.image) {
      return 5000;
    }
    return 10000;
  }
}
