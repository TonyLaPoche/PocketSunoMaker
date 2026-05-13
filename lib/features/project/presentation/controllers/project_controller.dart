import 'dart:io';

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
  static const int _maxTextAnimationDurationMs = 3000;
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
      final int inaccessibleSources = _countInaccessibleClipSources(value);
      state = state.copyWith(
        currentProject: value,
        isLoading: false,
        errorMessage: inaccessibleSources == 0
            ? null
            : 'Projet charge, mais $inaccessibleSources media(s) ne sont pas autorises par macOS. Reimporte-les pour les utiliser en preview/export.',
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
    final int durationMs = _clipDurationForAsset(asset);
    final Track targetTrack = Track(
      id: '${targetType.name}-track-${DateTime.now().millisecondsSinceEpoch}',
      type: targetType,
      index: tracks.length,
      name: null,
      clips: const <Clip>[],
    );
    final Clip newClip = Clip(
      id: 'clip-${DateTime.now().microsecondsSinceEpoch}',
      assetPath: asset.path,
      timelineStartMs: 0,
      sourceInMs: 0,
      sourceOutMs: durationMs,
    );

    final Track updatedTrack = targetTrack.copyWith(clips: <Clip>[newClip]);
    tracks.add(updatedTrack);

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

  void moveClipToTrack({
    required String sourceTrackId,
    required String targetTrackId,
    required String clipId,
  }) {
    if (sourceTrackId == targetTrackId) {
      return;
    }
    final Project? project = state.currentProject;
    if (project == null) {
      return;
    }

    final int sourceTrackIndex = project.tracks.indexWhere(
      (Track track) => track.id == sourceTrackId,
    );
    final int targetTrackIndex = project.tracks.indexWhere(
      (Track track) => track.id == targetTrackId,
    );
    if (sourceTrackIndex == -1 || targetTrackIndex == -1) {
      return;
    }

    final Track sourceTrack = project.tracks[sourceTrackIndex];
    final Track targetTrack = project.tracks[targetTrackIndex];
    final Clip? movingClip = sourceTrack.clips
        .where((Clip clip) => clip.id == clipId)
        .fold<Clip?>(null, (Clip? _, Clip clip) => clip);
    if (movingClip == null) {
      return;
    }
    if (sourceTrack.type != targetTrack.type) {
      return;
    }

    final List<Track> tracks = List<Track>.from(project.tracks);
    final List<Clip> sourceClips = sourceTrack.clips
        .where((Clip clip) => clip.id != clipId)
        .toList(growable: false);
    final List<Clip> targetClips = List<Clip>.from(targetTrack.clips)
      ..add(movingClip)
      ..sort(
        (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
      );

    tracks[sourceTrackIndex] = sourceTrack.copyWith(clips: sourceClips);
    tracks[targetTrackIndex] = targetTrack.copyWith(clips: targetClips);

    state = state.copyWith(
      currentProject: project.copyWith(
        tracks: tracks,
        durationMs: _computeProjectDurationMs(tracks),
      ),
      errorMessage: null,
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

  void updateClipInspectorValues({
    required String trackId,
    required String clipId,
    required double opacity,
    required double speed,
    required double volume,
    required double scale,
    required double rotationDeg,
    double? textPosXPx,
    double? textPosYPx,
    double? textFontSizePx,
    String? textFontFamily,
    bool? textBold,
    bool? textItalic,
    String? textColorHex,
    String? textBackgroundHex,
    bool? textShowBackground,
    bool? textShowBorder,
    TextAnimationType? textEntryAnimation,
    TextAnimationType? textExitAnimation,
    bool? textEntryFade,
    bool? textEntrySlideUp,
    bool? textEntrySlideDown,
    bool? textEntryZoom,
    bool? textExitFade,
    bool? textExitSlideUp,
    bool? textExitSlideDown,
    bool? textExitZoom,
    int? textEntryDurationMs,
    int? textExitDurationMs,
    double? textEntryOffsetPx,
    double? textExitOffsetPx,
    double? textEntryScale,
    double? textExitScale,
    bool? karaokeEnabled,
    String? karaokeFillColorHex,
    int? karaokeLeadInMs,
    int? karaokeSweepDurationMs,
    double? effectIntensity,
    double? effectShakeAmplitudePx,
    double? effectShakeFrequencyHz,
    bool? effectShakeAudioSync,
    bool? effectShakeAutoBpm,
    double? effectShakeDetectedBpm,
    double? effectGlitchTearStrength,
    double? effectGlitchNoiseAmount,
    String? effectGlitchColorAHex,
    String? effectGlitchColorBHex,
    bool? effectGlitchAutoColors,
    bool? effectGlitchAudioSync,
    double? effectGlitchLineMix,
    double? effectGlitchBlockMix,
    double? effectGlitchBlockSizePx,
  }) {
    _updateClip(
      trackId: trackId,
      clipId: clipId,
      update: (Clip clip) {
        return clip.copyWith(
          opacity: opacity.clamp(0.0, 1.0),
          speed: speed.clamp(0.25, 2.0),
          volume: volume.clamp(0.0, 2.0),
          scale: scale.clamp(0.5, 2.0),
          rotationDeg: rotationDeg.clamp(-180.0, 180.0),
          textPosXPx: textPosXPx?.clamp(-2000.0, 2000.0),
          textPosYPx: textPosYPx?.clamp(-2000.0, 2000.0),
          textFontSizePx: textFontSizePx?.clamp(12.0, 220.0),
          textFontFamily: textFontFamily,
          textBold: textBold,
          textItalic: textItalic,
          textColorHex: textColorHex,
          textBackgroundHex: textBackgroundHex,
          textShowBackground: textShowBackground,
          textShowBorder: textShowBorder,
          textEntryAnimation: textEntryAnimation,
          textExitAnimation: textExitAnimation,
          textEntryFade: textEntryFade,
          textEntrySlideUp: textEntrySlideUp,
          textEntrySlideDown: textEntrySlideDown,
          textEntryZoom: textEntryZoom,
          textExitFade: textExitFade,
          textExitSlideUp: textExitSlideUp,
          textExitSlideDown: textExitSlideDown,
          textExitZoom: textExitZoom,
          textEntryDurationMs: textEntryDurationMs == null
              ? null
              : _clampInt(textEntryDurationMs, 0, _maxTextAnimationDurationMs),
          textExitDurationMs: textExitDurationMs == null
              ? null
              : _clampInt(textExitDurationMs, 0, _maxTextAnimationDurationMs),
          textEntryOffsetPx: textEntryOffsetPx?.clamp(0.0, 180.0),
          textExitOffsetPx: textExitOffsetPx?.clamp(0.0, 180.0),
          textEntryScale: textEntryScale?.clamp(0.2, 1.0),
          textExitScale: textExitScale?.clamp(0.2, 1.0),
          karaokeEnabled: karaokeEnabled,
          karaokeFillColorHex: karaokeFillColorHex,
          karaokeLeadInMs: karaokeLeadInMs == null
              ? null
              : _clampInt(karaokeLeadInMs, 0, _maxTextAnimationDurationMs),
          karaokeSweepDurationMs: karaokeSweepDurationMs == null
              ? null
              : _clampInt(karaokeSweepDurationMs, 300, 10000),
          effectIntensity: effectIntensity?.clamp(0.1, 1.0),
          effectShakeAmplitudePx: effectShakeAmplitudePx?.clamp(2.0, 40.0),
          effectShakeFrequencyHz: effectShakeFrequencyHz?.clamp(4.0, 60.0),
          effectShakeAudioSync: effectShakeAudioSync,
          effectShakeAutoBpm: effectShakeAutoBpm,
          effectShakeDetectedBpm: effectShakeDetectedBpm?.clamp(60.0, 220.0),
          effectGlitchTearStrength: effectGlitchTearStrength?.clamp(0.05, 1.0),
          effectGlitchNoiseAmount: effectGlitchNoiseAmount?.clamp(0.0, 1.0),
          effectGlitchColorAHex: effectGlitchColorAHex,
          effectGlitchColorBHex: effectGlitchColorBHex,
          effectGlitchAutoColors: effectGlitchAutoColors,
          effectGlitchAudioSync: effectGlitchAudioSync,
          effectGlitchLineMix: effectGlitchLineMix?.clamp(0.0, 1.0),
          effectGlitchBlockMix: effectGlitchBlockMix?.clamp(0.0, 1.0),
          effectGlitchBlockSizePx: effectGlitchBlockSizePx?.clamp(6.0, 90.0),
        );
      },
    );
  }

  void addTextClipAt({
    required int startMs,
    String text = 'Nouveau texte',
    int durationMs = 3000,
    String? targetTrackId,
    bool forceCreateNewTrack = false,
  }) {
    final Project? project = state.currentProject;
    if (project == null) {
      return;
    }
    final List<Track> tracks = List<Track>.from(project.tracks);
    final int safeStartMs = startMs < 0 ? 0 : startMs;
    final int safeDurationMs = durationMs < _minClipDurationMs
        ? _minClipDurationMs
        : durationMs;
    final Track? existingTextTrack = forceCreateNewTrack
        ? null
        : targetTrackId == null
        ? tracks
              .where((Track track) => track.type == TrackType.text)
              .fold<Track?>(null, (Track? current, Track next) {
                if (current == null || next.index > current.index) {
                  return next;
                }
                return current;
              })
        : tracks
              .where((Track track) => track.id == targetTrackId)
              .fold<Track?>(
                null,
                (Track? current, Track next) =>
                    next.type == TrackType.text ? next : current,
              );
    final Clip textClip = Clip(
      id: 'clip-${DateTime.now().microsecondsSinceEpoch}',
      assetPath: '',
      timelineStartMs: safeStartMs,
      sourceInMs: 0,
      sourceOutMs: safeDurationMs,
      textContent: text,
    );
    if (existingTextTrack == null) {
      final Track newTextTrack = Track(
        id: 'text-track-${DateTime.now().millisecondsSinceEpoch}',
        type: TrackType.text,
        index: tracks.length,
        name: _defaultTextTrackName(tracks),
        clips: <Clip>[textClip],
      );
      tracks.add(newTextTrack);
    } else {
      final int trackIndex = tracks.indexWhere(
        (Track track) => track.id == existingTextTrack.id,
      );
      if (trackIndex == -1) {
        return;
      }
      final List<Clip> clips = List<Clip>.from(existingTextTrack.clips)
        ..add(textClip);
      clips.sort(
        (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
      );
      tracks[trackIndex] = existingTextTrack.copyWith(clips: clips);
    }
    state = state.copyWith(
      currentProject: project.copyWith(
        tracks: tracks,
        durationMs: _computeProjectDurationMs(tracks),
      ),
      errorMessage: null,
    );
  }

  void addVisualEffectClipAt({
    required int startMs,
    required VisualEffectType effectType,
    int durationMs = 2000,
    String? targetTrackId,
    bool forceCreateNewTrack = false,
  }) {
    _addEffectClipAt(
      startMs: startMs,
      durationMs: durationMs,
      targetType: TrackType.visualEffect,
      targetTrackId: targetTrackId,
      forceCreateNewTrack: forceCreateNewTrack,
      buildClip: (int safeStartMs, int safeDurationMs) => Clip(
        id: 'clip-${DateTime.now().microsecondsSinceEpoch}',
        assetPath: '',
        timelineStartMs: safeStartMs,
        sourceInMs: 0,
        sourceOutMs: safeDurationMs,
        visualEffectType: effectType,
      ),
      defaultTrackNameBuilder: _defaultVisualEffectTrackName,
    );
  }

  void addAudioEffectClipAt({
    required int startMs,
    required AudioEffectType effectType,
    int durationMs = 1200,
    String? targetTrackId,
    bool forceCreateNewTrack = false,
  }) {
    _addEffectClipAt(
      startMs: startMs,
      durationMs: durationMs,
      targetType: TrackType.audioEffect,
      targetTrackId: targetTrackId,
      forceCreateNewTrack: forceCreateNewTrack,
      buildClip: (int safeStartMs, int safeDurationMs) => Clip(
        id: 'clip-${DateTime.now().microsecondsSinceEpoch}',
        assetPath: '',
        timelineStartMs: safeStartMs,
        sourceInMs: 0,
        sourceOutMs: safeDurationMs,
        audioEffectType: effectType,
      ),
      defaultTrackNameBuilder: _defaultAudioEffectTrackName,
    );
  }

  void renameTextClip({
    required String trackId,
    required String clipId,
    required String name,
  }) {
    updateClipTextContent(trackId: trackId, clipId: clipId, text: name);
  }

  void renameTrack({required String trackId, required String name}) {
    final Project? project = state.currentProject;
    if (project == null) {
      return;
    }
    final String sanitized = name.trim();
    if (sanitized.isEmpty) {
      return;
    }
    final List<Track> tracks = project.tracks
        .map((Track track) {
          if (track.id != trackId) {
            return track;
          }
          return track.copyWith(name: sanitized);
        })
        .toList(growable: false);
    state = state.copyWith(
      currentProject: project.copyWith(
        tracks: tracks,
        durationMs: _computeProjectDurationMs(tracks),
      ),
      errorMessage: null,
    );
  }

  void _addEffectClipAt({
    required int startMs,
    required int durationMs,
    required TrackType targetType,
    required String? targetTrackId,
    required bool forceCreateNewTrack,
    required Clip Function(int safeStartMs, int safeDurationMs) buildClip,
    required String Function(List<Track>) defaultTrackNameBuilder,
  }) {
    final Project? project = state.currentProject;
    if (project == null) {
      return;
    }
    final List<Track> tracks = List<Track>.from(project.tracks);
    final int safeStartMs = startMs < 0 ? 0 : startMs;
    final int safeDurationMs = durationMs < _minClipDurationMs
        ? _minClipDurationMs
        : durationMs;
    final Track? existingTrack = forceCreateNewTrack
        ? null
        : targetTrackId == null
        ? tracks.where((Track track) => track.type == targetType).fold<Track?>(
            null,
            (Track? current, Track next) {
              if (current == null || next.index > current.index) {
                return next;
              }
              return current;
            },
          )
        : tracks
              .where((Track track) => track.id == targetTrackId)
              .fold<Track?>(
                null,
                (Track? current, Track next) =>
                    next.type == targetType ? next : current,
              );

    final Clip effectClip = buildClip(safeStartMs, safeDurationMs);
    if (existingTrack == null) {
      tracks.add(
        Track(
          id: '${targetType.name}-track-${DateTime.now().millisecondsSinceEpoch}',
          type: targetType,
          index: tracks.length,
          name: defaultTrackNameBuilder(tracks),
          clips: <Clip>[effectClip],
        ),
      );
    } else {
      final int trackIndex = tracks.indexWhere(
        (Track track) => track.id == existingTrack.id,
      );
      if (trackIndex == -1) {
        return;
      }
      final List<Clip> clips = List<Clip>.from(existingTrack.clips)
        ..add(effectClip)
        ..sort(
          (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
        );
      tracks[trackIndex] = existingTrack.copyWith(clips: clips);
    }

    state = state.copyWith(
      currentProject: project.copyWith(
        tracks: tracks,
        durationMs: _computeProjectDurationMs(tracks),
      ),
      errorMessage: null,
    );
  }

  void updateClipTextContent({
    required String trackId,
    required String clipId,
    required String text,
  }) {
    final String sanitized = text.trim();
    if (sanitized.isEmpty) {
      return;
    }
    _updateClip(
      trackId: trackId,
      clipId: clipId,
      update: (Clip clip) => clip.copyWith(textContent: sanitized),
    );
  }

  void moveTextClipByDelta({
    required String trackId,
    required String clipId,
    required double deltaXPx,
    required double deltaYPx,
  }) {
    _updateClip(
      trackId: trackId,
      clipId: clipId,
      update: (Clip clip) => clip.copyWith(
        textPosXPx: (clip.textPosXPx + deltaXPx).clamp(-2000.0, 2000.0),
        textPosYPx: (clip.textPosYPx + deltaYPx).clamp(-2000.0, 2000.0),
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

  String _defaultTextTrackName(List<Track> tracks) {
    final int count =
        tracks.where((Track track) => track.type == TrackType.text).length + 1;
    return 'Texte $count';
  }

  String _defaultVisualEffectTrackName(List<Track> tracks) {
    final int count =
        tracks
            .where((Track track) => track.type == TrackType.visualEffect)
            .length +
        1;
    return 'Effets visuels $count';
  }

  String _defaultAudioEffectTrackName(List<Track> tracks) {
    final int count =
        tracks
            .where((Track track) => track.type == TrackType.audioEffect)
            .length +
        1;
    return 'Effets sonores $count';
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

  int _countInaccessibleClipSources(Project project) {
    final Set<String> uniquePaths = project.tracks
        .where((Track track) => track.type != TrackType.text)
        .expand((Track track) => track.clips)
        .map((Clip clip) => clip.assetPath)
        .where((String path) => path.isNotEmpty)
        .toSet();
    int inaccessible = 0;
    for (final String path in uniquePaths) {
      final File file = File(path);
      if (!file.existsSync()) {
        inaccessible++;
        continue;
      }
      try {
        final RandomAccessFile raf = file.openSync(mode: FileMode.read);
        raf.closeSync();
      } on FileSystemException {
        inaccessible++;
      }
    }
    return inaccessible;
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
