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
  static const int _minClipDurationMs = 500;
  static const int _snapThresholdMs = 120;

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

  void moveClipByDelta({
    required String trackId,
    required String clipId,
    required int deltaMs,
    bool useSnapping = true,
  }) {
    final Project? project = state.currentProject;
    if (project == null) {
      return;
    }

    final List<Track> updatedTracks = project.tracks
        .map((Track track) {
          if (track.id != trackId) {
            return track;
          }

          final List<Clip> updatedClips = track.clips
              .map((Clip clip) {
                if (clip.id != clipId) {
                  return clip;
                }
                final int rawDelta = deltaMs < -clip.timelineStartMs
                    ? -clip.timelineStartMs
                    : deltaMs;
                final int candidateStart = clip.timelineStartMs + rawDelta;
                final int nextStart = useSnapping
                    ? _snapStartMs(
                        trackId: trackId,
                        clipId: clipId,
                        candidateStartMs: candidateStart,
                        clipDurationMs: clip.durationMs,
                      )
                    : candidateStart;
                final int safeStart = nextStart < 0 ? 0 : nextStart;
                return clip.copyWith(timelineStartMs: safeStart);
              })
              .toList(growable: false);

          return track.copyWith(clips: updatedClips);
        })
        .toList(growable: false);

    final int projectDurationMs = _computeProjectDurationMs(updatedTracks);
    state = state.copyWith(
      currentProject: project.copyWith(
        tracks: updatedTracks,
        durationMs: projectDurationMs,
      ),
    );
  }

  void removeClip({required String trackId, required String clipId}) {
    final Project? project = state.currentProject;
    if (project == null) {
      return;
    }

    final List<Track> tracks = project.tracks
        .map((Track track) {
          if (track.id != trackId) {
            return track;
          }
          final List<Clip> remainingClips = track.clips
              .where((Clip clip) => clip.id != clipId)
              .toList(growable: false);
          return track.copyWith(clips: remainingClips);
        })
        .where((Track track) => track.clips.isNotEmpty)
        .toList(growable: false);

    final List<Track> normalizedTracks = <Track>[
      for (int index = 0; index < tracks.length; index++)
        tracks[index].copyWith(index: index),
    ];

    state = state.copyWith(
      currentProject: project.copyWith(
        tracks: normalizedTracks,
        durationMs: _computeProjectDurationMs(normalizedTracks),
      ),
    );
  }

  void trimClipStartByDelta({
    required String trackId,
    required String clipId,
    required int deltaMs,
    bool useSnapping = true,
  }) {
    _updateClip(
      trackId: trackId,
      clipId: clipId,
      update: (Clip clip) {
        final int lowerBoundDelta = _maxInt(
          -clip.sourceInMs,
          -clip.timelineStartMs,
        );
        final int upperBoundDelta = clip.durationMs - _minClipDurationMs;
        final int clampedDelta = _clampInt(
          deltaMs,
          lowerBoundDelta,
          upperBoundDelta,
        );
        final int candidateStart = clip.timelineStartMs + clampedDelta;
        final int candidateDuration = clip.durationMs - clampedDelta;
        final int snappedStart = useSnapping
            ? _snapStartMs(
                trackId: trackId,
                clipId: clipId,
                candidateStartMs: candidateStart,
                clipDurationMs: candidateDuration,
              )
            : candidateStart;
        final int snappedDelta = snappedStart - clip.timelineStartMs;
        final int appliedDelta = _clampInt(
          snappedDelta,
          lowerBoundDelta,
          upperBoundDelta,
        );
        return clip.copyWith(
          sourceInMs: clip.sourceInMs + appliedDelta,
          timelineStartMs: clip.timelineStartMs + appliedDelta,
        );
      },
    );
  }

  void trimClipEndByDelta({
    required String trackId,
    required String clipId,
    required int deltaMs,
    bool useSnapping = true,
  }) {
    _updateClip(
      trackId: trackId,
      clipId: clipId,
      update: (Clip clip) {
        final int lowerBoundDelta = -(clip.durationMs - _minClipDurationMs);
        final int clampedDelta = deltaMs < lowerBoundDelta
            ? lowerBoundDelta
            : deltaMs;
        final int candidateEnd =
            clip.timelineStartMs + clip.durationMs + clampedDelta;
        final int snappedEnd = useSnapping
            ? _snapEndMs(
                trackId: trackId,
                clipId: clipId,
                candidateEndMs: candidateEnd,
              )
            : candidateEnd;
        final int snappedDelta =
            snappedEnd - (clip.timelineStartMs + clip.durationMs);
        final int appliedDelta = snappedDelta < lowerBoundDelta
            ? lowerBoundDelta
            : snappedDelta;
        return clip.copyWith(sourceOutMs: clip.sourceOutMs + appliedDelta);
      },
    );
  }

  void splitClipAtPlayhead({
    required String trackId,
    required String clipId,
    required int playheadMs,
  }) {
    final Project? project = state.currentProject;
    if (project == null) {
      return;
    }

    final List<Track> updatedTracks = project.tracks
        .map((Track track) {
          if (track.id != trackId) {
            return track;
          }

          final List<Clip> nextClips = <Clip>[];
          for (final Clip clip in track.clips) {
            if (clip.id != clipId) {
              nextClips.add(clip);
              continue;
            }

            final int clipStart = clip.timelineStartMs;
            final int clipEnd = clip.timelineStartMs + clip.durationMs;
            if (playheadMs <= clipStart || playheadMs >= clipEnd) {
              nextClips.add(clip);
              continue;
            }

            final int leftDurationMs = playheadMs - clipStart;
            final int rightDurationMs = clipEnd - playheadMs;
            if (leftDurationMs < _minClipDurationMs ||
                rightDurationMs < _minClipDurationMs) {
              nextClips.add(clip);
              continue;
            }

            final int sourceSplitMs = clip.sourceInMs + leftDurationMs;
            final Clip leftClip = clip.copyWith(sourceOutMs: sourceSplitMs);
            final Clip rightClip = clip.copyWith(
              id: 'clip-${DateTime.now().microsecondsSinceEpoch}',
              timelineStartMs: playheadMs,
              sourceInMs: sourceSplitMs,
            );
            nextClips
              ..add(leftClip)
              ..add(rightClip);
          }

          return track.copyWith(clips: nextClips);
        })
        .toList(growable: false);

    state = state.copyWith(
      currentProject: project.copyWith(
        tracks: updatedTracks,
        durationMs: _computeProjectDurationMs(updatedTracks),
      ),
    );
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

  void _updateClip({
    required String trackId,
    required String clipId,
    required Clip Function(Clip clip) update,
  }) {
    final Project? project = state.currentProject;
    if (project == null) {
      return;
    }

    final List<Track> updatedTracks = project.tracks
        .map((Track track) {
          if (track.id != trackId) {
            return track;
          }

          final List<Clip> updatedClips = track.clips
              .map((Clip clip) {
                if (clip.id != clipId) {
                  return clip;
                }
                return update(clip);
              })
              .toList(growable: false);

          return track.copyWith(clips: updatedClips);
        })
        .toList(growable: false);

    state = state.copyWith(
      currentProject: project.copyWith(
        tracks: updatedTracks,
        durationMs: _computeProjectDurationMs(updatedTracks),
      ),
    );
  }

  int _clampInt(int value, int min, int max) {
    if (max < min) {
      return min;
    }
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  int _maxInt(int a, int b) => a > b ? a : b;

  int _snapStartMs({
    required String trackId,
    required String clipId,
    required int candidateStartMs,
    required int clipDurationMs,
  }) {
    final int candidateEndMs = candidateStartMs + clipDurationMs;
    final List<int> snapPoints = _collectSnapPoints(
      trackId: trackId,
      clipId: clipId,
    );
    final int? snappedStart = _findClosestSnap(
      candidateMs: candidateStartMs,
      points: snapPoints,
    );
    final int? snappedEnd = _findClosestSnap(
      candidateMs: candidateEndMs,
      points: snapPoints,
    );

    if (snappedStart == null && snappedEnd == null) {
      return candidateStartMs;
    }
    if (snappedStart != null && snappedEnd == null) {
      return snappedStart;
    }
    if (snappedStart == null && snappedEnd != null) {
      return snappedEnd - clipDurationMs;
    }

    final int deltaFromStart = (snappedStart! - candidateStartMs).abs();
    final int deltaFromEnd = (snappedEnd! - candidateEndMs).abs();
    if (deltaFromStart <= deltaFromEnd) {
      return snappedStart;
    }
    return snappedEnd - clipDurationMs;
  }

  int _snapEndMs({
    required String trackId,
    required String clipId,
    required int candidateEndMs,
  }) {
    final List<int> snapPoints = _collectSnapPoints(
      trackId: trackId,
      clipId: clipId,
    );
    return _findClosestSnap(candidateMs: candidateEndMs, points: snapPoints) ??
        candidateEndMs;
  }

  List<int> _collectSnapPoints({
    required String trackId,
    required String clipId,
  }) {
    final Project? project = state.currentProject;
    if (project == null) {
      return <int>[0];
    }

    final List<int> points = <int>[0];
    for (final Track track in project.tracks) {
      for (final Clip clip in track.clips) {
        if (track.id == trackId && clip.id == clipId) {
          continue;
        }
        points.add(clip.timelineStartMs);
        points.add(clip.timelineStartMs + clip.durationMs);
      }
    }
    return points;
  }

  int? _findClosestSnap({required int candidateMs, required List<int> points}) {
    int? bestPoint;
    int? bestDistance;
    for (final int point in points) {
      final int distance = (point - candidateMs).abs();
      if (distance > _snapThresholdMs) {
        continue;
      }
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestPoint = point;
      }
    }
    return bestPoint;
  }
}
