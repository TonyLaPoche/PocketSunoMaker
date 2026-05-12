import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../../export/domain/entities/export_job.dart';
import '../../../export/presentation/controllers/export_queue_controller.dart';
import '../../../export/presentation/controllers/export_queue_state.dart';
import '../../../media_import/presentation/controllers/media_import_controller.dart';
import '../../../media_import/presentation/widgets/media_bin_panel.dart';
import '../../../preview/presentation/controllers/preview_controller.dart';
import '../../../preview/presentation/controllers/preview_audio_sync_controller.dart';
import '../../../preview/presentation/controllers/preview_state.dart';
import '../../../preview/presentation/widgets/preview_panel.dart';
import '../../../preview/presentation/utils/preview_clip_resolver.dart';
import '../../domain/entities/clip.dart';
import '../../domain/entities/export_preset.dart';
import '../../domain/entities/project.dart';
import '../../domain/entities/track.dart';
import '../controllers/project_controller.dart';
import '../controllers/project_state.dart';
import '../widgets/timeline_panel.dart';

class ProjectHomePage extends ConsumerStatefulWidget {
  const ProjectHomePage({super.key});

  @override
  ConsumerState<ProjectHomePage> createState() => _ProjectHomePageState();
}

class _ProjectHomePageState extends ConsumerState<ProjectHomePage> {
  String? _inspectedTrackId;
  Clip? _inspectedClip;
  bool _comfortModeEnabled = true;
  bool _previewGuidesEnabled = false;
  double _timelineHeightPx = 300;
  final Map<String, _ClipInspectorValues> _inspectorByClipId =
      <String, _ClipInspectorValues>{};
  static const double _minTimelineHeightPx = 180;
  static const double _minTopPanelsHeightPx = 220;

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      projectControllerProvider.select(
        (state) => state.currentProject?.durationMs ?? 0,
      ),
      (_, int durationMs) {
        ref.read(previewControllerProvider.notifier).setDuration(durationMs);
      },
    );
    ref.listen(
      previewControllerProvider.select(
        (previewState) =>
            (previewState.currentPositionMs, previewState.isPlaying),
      ),
      (_, (int, bool) previewTuple) {
        final Project? project = ref
            .read(projectControllerProvider)
            .currentProject;
        final _ClipInspectorValues activeValues = _activeInspectorValues(
          project,
          previewTuple.$1,
        );
        ref
            .read(previewControllerProvider.notifier)
            .setPlaybackSpeed(activeValues.speed);
        ref
            .read(previewAudioSyncControllerProvider)
            .synchronize(
              project: project,
              positionMs: previewTuple.$1,
              shouldPlay: previewTuple.$2,
              volume: activeValues.volume,
              speed: activeValues.speed,
            );
      },
    );
    ref.listen(
      projectControllerProvider.select((state) => state.currentProject),
      (_, Project? project) {
        final previewState = ref.read(previewControllerProvider);
        final _ClipInspectorValues activeValues = _activeInspectorValues(
          project,
          previewState.currentPositionMs,
        );
        ref
            .read(previewControllerProvider.notifier)
            .setPlaybackSpeed(activeValues.speed);
        ref
            .read(mediaImportControllerProvider.notifier)
            .synchronizeFromProject(project);
        ref
            .read(previewAudioSyncControllerProvider)
            .synchronize(
              project: project,
              positionMs: previewState.currentPositionMs,
              shouldPlay: previewState.isPlaying,
              volume: activeValues.volume,
              speed: activeValues.speed,
            );
      },
    );

    final projectState = ref.watch(projectControllerProvider);
    final projectController = ref.read(projectControllerProvider.notifier);
    final mediaState = ref.watch(mediaImportControllerProvider);
    final mediaController = ref.read(mediaImportControllerProvider.notifier);
    final previewState = ref.watch(previewControllerProvider);
    final previewController = ref.read(previewControllerProvider.notifier);
    final exportState = ref.watch(exportQueueControllerProvider);
    final exportController = ref.read(exportQueueControllerProvider.notifier);
    final Project? project = projectState.currentProject;
    ExportJob? runningExportJob;
    int queuedExportsCount = 0;
    for (final ExportJob job in exportState.jobs) {
      if (job.status == ExportJobStatus.running) {
        runningExportJob = job;
      }
      if (job.status == ExportJobStatus.queued) {
        queuedExportsCount++;
      }
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (previewState.durationMs > 0) {
            previewController.togglePlayPause();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () {
          unawaited(projectController.createNewProject());
        },
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () {
          unawaited(mediaController.pickMediaFiles());
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          unawaited(projectController.saveCurrentProject());
        },
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () {
          unawaited(projectController.loadProjectFromDisk());
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          final int target = (previewState.currentPositionMs - 1000).clamp(
            0,
            previewState.durationMs,
          );
          previewController.seekTo(target);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          final int target = (previewState.currentPositionMs + 1000).clamp(
            0,
            previewState.durationMs,
          );
          previewController.seekTo(target);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              children: <Widget>[
                _StudioTopBar(
                  isProjectLoading: projectState.isLoading,
                  isMediaLoading: mediaState.isLoading,
                  comfortModeEnabled: _comfortModeEnabled,
                  onCreateProject: projectController.createNewProject,
                  onImportMedia: mediaController.pickMediaFiles,
                  onSaveProject: projectController.saveCurrentProject,
                  onLoadProject: projectController.loadProjectFromDisk,
                  onToggleComfortMode: (bool enabled) {
                    setState(() {
                      _comfortModeEnabled = enabled;
                    });
                  },
                ),
                const SizedBox(height: 8),
                if (projectState.errorMessage != null ||
                    mediaState.errorMessage != null)
                  _ErrorBanner(
                    message:
                        projectState.errorMessage ?? mediaState.errorMessage!,
                  ),
                if (projectState.errorMessage != null ||
                    mediaState.errorMessage != null)
                  const SizedBox(height: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      const double spacing = 8;
                      const double handleHeight = 14;
                      final double maxTimelineHeight = math.max(
                        _minTimelineHeightPx,
                        constraints.maxHeight -
                            _minTopPanelsHeightPx -
                            spacing * 2 -
                            handleHeight,
                      );
                      final double timelineHeight = _timelineHeightPx
                          .clamp(_minTimelineHeightPx, maxTimelineHeight)
                          .toDouble();
                      final double topPanelsHeight =
                          constraints.maxHeight -
                          timelineHeight -
                          spacing * 2 -
                          handleHeight;
                      return Column(
                        children: <Widget>[
                          SizedBox(
                            height: topPanelsHeight,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                SizedBox(
                                  width: 300,
                                  child: _PanelShell(
                                    title: 'Medias',
                                    comfortModeEnabled: _comfortModeEnabled,
                                    child: _MediaToolsTabs(
                                      project: project,
                                      mediaChild: DropTarget(
                                        onDragEntered: (_) => mediaController
                                            .setDraggingOver(true),
                                        onDragExited: (_) => mediaController
                                            .setDraggingOver(false),
                                        onDragDone: (DropDoneDetails details) {
                                          final List<String> paths = details
                                              .files
                                              .map((file) => file.path)
                                              .toList();
                                          mediaController.setDraggingOver(
                                            false,
                                          );
                                          mediaController.importDroppedFiles(
                                            paths,
                                          );
                                        },
                                        child: MediaBinPanel(
                                          assets: mediaState.assets,
                                          isLoading: mediaState.isLoading,
                                          canAddToTimeline: project != null,
                                          onAddToTimeline: projectController
                                              .addAssetToTimeline,
                                          onRemoveAsset: (asset) =>
                                              mediaController.removeAssetById(
                                                asset.id,
                                              ),
                                        ),
                                      ),
                                      onAddTextAtPlayhead: project == null
                                          ? null
                                          : ({
                                              String? targetTrackId,
                                              bool createNewTrack = false,
                                            }) {
                                              projectController.addTextClipAt(
                                                startMs: previewState
                                                    .currentPositionMs,
                                                targetTrackId: targetTrackId,
                                                forceCreateNewTrack:
                                                    createNewTrack,
                                              );
                                            },
                                      onAddVisualEffectAtPlayhead:
                                          project == null
                                          ? null
                                          : ({
                                              required VisualEffectType
                                              effectType,
                                              String? targetTrackId,
                                              bool createNewTrack = false,
                                            }) {
                                              projectController
                                                  .addVisualEffectClipAt(
                                                    startMs: previewState
                                                        .currentPositionMs,
                                                    effectType: effectType,
                                                    targetTrackId:
                                                        targetTrackId,
                                                    forceCreateNewTrack:
                                                        createNewTrack,
                                                  );
                                            },
                                      onAddAudioEffectAtPlayhead:
                                          project == null
                                          ? null
                                          : ({
                                              required AudioEffectType
                                              effectType,
                                              String? targetTrackId,
                                              bool createNewTrack = false,
                                            }) {
                                              projectController
                                                  .addAudioEffectClipAt(
                                                    startMs: previewState
                                                        .currentPositionMs,
                                                    effectType: effectType,
                                                    targetTrackId:
                                                        targetTrackId,
                                                    forceCreateNewTrack:
                                                        createNewTrack,
                                                  );
                                            },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _PanelShell(
                                    title: 'Lecteur',
                                    comfortModeEnabled: _comfortModeEnabled,
                                    child: PreviewPanel(
                                      project: project,
                                      state: previewState,
                                      onTogglePlayPause:
                                          previewController.togglePlayPause,
                                      onScrubStart:
                                          previewController.beginScrub,
                                      onScrubEnd: previewController.endScrub,
                                      onSeekTo: previewController.seekTo,
                                      selectedTextClipId:
                                          _inspectedTrackType(project) ==
                                              TrackType.text
                                          ? _inspectedClip?.id
                                          : null,
                                      onTextClipSelected:
                                          (String trackId, Clip clip) {
                                            setState(() {
                                              _inspectedTrackId = trackId;
                                              _inspectedClip = clip;
                                              _inspectorByClipId.putIfAbsent(
                                                clip.id,
                                                () =>
                                                    _ClipInspectorValues.fromClip(
                                                      clip,
                                                    ),
                                              );
                                            });
                                          },
                                      onMoveSelectedTextByDelta: (Offset delta) {
                                        final String? trackId =
                                            _inspectedTrackId;
                                        final Clip? clip = _inspectedClip;
                                        if (trackId == null ||
                                            clip == null ||
                                            _inspectedTrackType(project) !=
                                                TrackType.text) {
                                          return;
                                        }
                                        setState(() {
                                          _inspectedClip = clip.copyWith(
                                            textPosXPx:
                                                clip.textPosXPx + delta.dx,
                                            textPosYPx:
                                                clip.textPosYPx + delta.dy,
                                          );
                                          _inspectorByClipId[clip.id] =
                                              (_inspectorByClipId[clip.id] ??
                                                      _ClipInspectorValues.fromClip(
                                                        clip,
                                                      ))
                                                  .copyWith(
                                                    textPosXPx:
                                                        (_inspectorByClipId[clip
                                                                    .id]
                                                                ?.textPosXPx ??
                                                            clip.textPosXPx) +
                                                        delta.dx,
                                                    textPosYPx:
                                                        (_inspectorByClipId[clip
                                                                    .id]
                                                                ?.textPosYPx ??
                                                            clip.textPosYPx) +
                                                        delta.dy,
                                                  );
                                        });
                                        projectController.moveTextClipByDelta(
                                          trackId: trackId,
                                          clipId: clip.id,
                                          deltaXPx: delta.dx,
                                          deltaYPx: delta.dy,
                                        );
                                      },
                                      showGuides: _previewGuidesEnabled,
                                      outputWidth:
                                          exportState.selectedPreset.width,
                                      outputHeight:
                                          exportState.selectedPreset.height,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 280,
                                  child: _PanelShell(
                                    title: 'Panneau droit',
                                    comfortModeEnabled: _comfortModeEnabled,
                                    child: _InspectorExportTabs(
                                      project: project,
                                      previewState: previewState,
                                      projectState: projectState,
                                      exportState: exportState,
                                      runningExportJob: runningExportJob,
                                      queuedExportsCount: queuedExportsCount,
                                      inspectedTrackId: _inspectedTrackId,
                                      inspectedTrackType: _inspectedTrackType(
                                        project,
                                      ),
                                      inspectedClip: _inspectedClip,
                                      inspectorByClipId: _inspectorByClipId,
                                      previewGuidesEnabled:
                                          _previewGuidesEnabled,
                                      onSelectPreset:
                                          exportController.selectPreset,
                                      onEnqueueExport: project == null
                                          ? null
                                          : () => exportController
                                                .enqueueExport(project),
                                      onCancelRunningExport:
                                          exportController.cancelRunningExport,
                                      statusLabelBuilder: _statusLabel,
                                      statusColorBuilder: _statusColor,
                                      onInspectorChanged:
                                          (_ClipInspectorValues values) {
                                            final String? trackId =
                                                _inspectedTrackId;
                                            final Clip? inspectedClip =
                                                _inspectedClip;
                                            if (trackId == null ||
                                                inspectedClip == null) {
                                              return;
                                            }
                                            setState(() {
                                              _inspectorByClipId[inspectedClip
                                                      .id] =
                                                  values;
                                            });
                                            projectController
                                                .updateClipInspectorValues(
                                                  trackId: trackId,
                                                  clipId: inspectedClip.id,
                                                  opacity: values.opacity,
                                                  speed: values.speed,
                                                  volume: values.volume,
                                                  scale: values.scale,
                                                  rotationDeg:
                                                      values.rotationDeg,
                                                  textPosXPx: values.textPosXPx,
                                                  textPosYPx: values.textPosYPx,
                                                  textFontSizePx:
                                                      values.textFontSizePx,
                                                  textFontFamily:
                                                      values.textFontFamily,
                                                  textBold: values.textBold,
                                                  textItalic: values.textItalic,
                                                  textColorHex:
                                                      values.textColorHex,
                                                  textBackgroundHex:
                                                      values.textBackgroundHex,
                                                  textShowBackground:
                                                      values.textShowBackground,
                                                  textShowBorder:
                                                      values.textShowBorder,
                                                  textEntryAnimation:
                                                      values.textEntryAnimation,
                                                  textExitAnimation:
                                                      values.textExitAnimation,
                                                  textEntryFade:
                                                      values.textEntryFade,
                                                  textEntrySlideUp:
                                                      values.textEntrySlideUp,
                                                  textEntrySlideDown:
                                                      values.textEntrySlideDown,
                                                  textEntryZoom:
                                                      values.textEntryZoom,
                                                  textExitFade:
                                                      values.textExitFade,
                                                  textExitSlideUp:
                                                      values.textExitSlideUp,
                                                  textExitSlideDown:
                                                      values.textExitSlideDown,
                                                  textExitZoom:
                                                      values.textExitZoom,
                                                  textEntryDurationMs: values
                                                      .textEntryDurationMs
                                                      .round(),
                                                  textExitDurationMs: values
                                                      .textExitDurationMs
                                                      .round(),
                                                  textEntryOffsetPx:
                                                      values.textEntryOffsetPx,
                                                  textExitOffsetPx:
                                                      values.textExitOffsetPx,
                                                  textEntryScale:
                                                      values.textEntryScale,
                                                  textExitScale:
                                                      values.textExitScale,
                                                  karaokeEnabled:
                                                      values.karaokeEnabled,
                                                  karaokeFillColorHex: values
                                                      .karaokeFillColorHex,
                                                  karaokeLeadInMs: values
                                                      .karaokeLeadInMs
                                                      .round(),
                                                  karaokeSweepDurationMs: values
                                                      .karaokeSweepDurationMs
                                                      .round(),
                                                  effectIntensity:
                                                      values.effectIntensity,
                                                );
                                            final _ClipInspectorValues
                                            activeValues =
                                                _activeInspectorValues(
                                                  project,
                                                  previewState
                                                      .currentPositionMs,
                                                );
                                            ref
                                                .read(
                                                  previewControllerProvider
                                                      .notifier,
                                                )
                                                .setPlaybackSpeed(
                                                  activeValues.speed,
                                                );
                                            ref
                                                .read(
                                                  previewAudioSyncControllerProvider,
                                                )
                                                .synchronize(
                                                  project: project,
                                                  positionMs: previewState
                                                      .currentPositionMs,
                                                  shouldPlay:
                                                      previewState.isPlaying,
                                                  volume: activeValues.volume,
                                                  speed: activeValues.speed,
                                                );
                                          },
                                      onEditText:
                                          (_inspectedTrackType(project) ==
                                                  TrackType.text &&
                                              _inspectedTrackId != null &&
                                              _inspectedClip != null)
                                          ? () {
                                              _showEditTextDialog(
                                                context: context,
                                                projectController:
                                                    projectController,
                                                trackId: _inspectedTrackId!,
                                                clip: _inspectedClip!,
                                              );
                                            }
                                          : null,
                                      onTogglePreviewGuides: (bool enabled) {
                                        setState(() {
                                          _previewGuidesEnabled = enabled;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: spacing),
                          _TimelineResizeHandle(
                            onVerticalDragUpdate: (double deltaDy) {
                              setState(() {
                                _timelineHeightPx =
                                    (_timelineHeightPx - deltaDy)
                                        .clamp(
                                          _minTimelineHeightPx,
                                          maxTimelineHeight,
                                        )
                                        .toDouble();
                              });
                            },
                          ),
                          const SizedBox(height: spacing),
                          SizedBox(
                            height: timelineHeight,
                            width: double.infinity,
                            child: _PanelShell(
                              title: 'Timeline',
                              comfortModeEnabled: _comfortModeEnabled,
                              headerTrailing: IconButton(
                                tooltip: 'Aide outils timeline',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.help_outline, size: 18),
                                onPressed: () {
                                  _showTimelineToolsHelpDialog(context);
                                },
                              ),
                              child: TimelinePanel(
                                project: project,
                                playheadMs: previewState.currentPositionMs,
                                isPlaying: previewState.isPlaying,
                                onSeekTo: previewController.seekTo,
                                reducedVisualIntensity: _comfortModeEnabled,
                                onClipSelectionChanged:
                                    (String? trackId, Clip? clip) {
                                      setState(() {
                                        _inspectedTrackId = trackId;
                                        _inspectedClip = clip;
                                        if (clip != null) {
                                          _inspectorByClipId.putIfAbsent(
                                            clip.id,
                                            () => _ClipInspectorValues.fromClip(
                                              clip,
                                            ),
                                          );
                                        }
                                      });
                                    },
                                onMoveClipByDelta:
                                    projectController.moveClipByDelta,
                                onTrimClipStartByDelta:
                                    projectController.trimClipStartByDelta,
                                onTrimClipEndByDelta:
                                    projectController.trimClipEndByDelta,
                                onSplitClipAtPlayhead:
                                    projectController.splitClipAtPlayhead,
                                onMoveClipToTrack:
                                    projectController.moveClipToTrack,
                                onRenameTextClipRequested:
                                    ({
                                      required String trackId,
                                      required Clip clip,
                                    }) {
                                      _showEditTextDialog(
                                        context: context,
                                        projectController: projectController,
                                        trackId: trackId,
                                        clip: clip,
                                      );
                                    },
                                onRenameTrackRequested:
                                    ({required Track track}) {
                                      _showRenameTrackDialog(
                                        context: context,
                                        projectController: projectController,
                                        track: track,
                                      );
                                    },
                                onRemoveClip: projectController.removeClip,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                _StudioStatusBar(
                  isPlaying: previewState.isPlaying,
                  currentPositionMs: previewState.currentPositionMs,
                  projectName: project?.name,
                  exportJobsCount: exportState.jobs.length,
                  isExporting: exportState.isProcessing,
                  activeExportLabel: runningExportJob?.presetLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(ExportJobStatus status) {
    switch (status) {
      case ExportJobStatus.queued:
        return 'en attente';
      case ExportJobStatus.running:
        return 'en cours';
      case ExportJobStatus.succeeded:
        return 'termine';
      case ExportJobStatus.failed:
        return 'echec';
      case ExportJobStatus.canceled:
        return 'annule';
    }
  }

  Color _statusColor(BuildContext context, ExportJobStatus status) {
    switch (status) {
      case ExportJobStatus.queued:
        return context.cyberpunk.textMuted;
      case ExportJobStatus.running:
        return context.cyberpunk.neonBlue;
      case ExportJobStatus.succeeded:
        return Colors.greenAccent.shade400;
      case ExportJobStatus.failed:
        return Theme.of(context).colorScheme.error;
      case ExportJobStatus.canceled:
        return Colors.orangeAccent.shade200;
    }
  }

  _ClipInspectorValues _activeInspectorValues(
    Project? project,
    int positionMs,
  ) {
    final Clip? inspectedClip = _inspectedClip;
    if (project == null || inspectedClip == null) {
      return _ClipInspectorValues.defaults;
    }
    final String inspectedClipId = inspectedClip.id;
    final String? activeVideoClipId = findActiveClip(
      project: project,
      positionMs: positionMs,
      type: TrackType.video,
    )?.clip.id;
    final String? activeAudioClipId = findActiveClip(
      project: project,
      positionMs: positionMs,
      type: TrackType.audio,
    )?.clip.id;
    final bool isActive =
        inspectedClipId == activeVideoClipId ||
        inspectedClipId == activeAudioClipId;
    if (!isActive) {
      return _ClipInspectorValues.defaults;
    }
    return _inspectorByClipId[inspectedClipId] ??
        _ClipInspectorValues.fromClip(inspectedClip);
  }

  TrackType? _inspectedTrackType(Project? project) {
    final String? trackId = _inspectedTrackId;
    if (project == null || trackId == null) {
      return null;
    }
    for (final Track track in project.tracks) {
      if (track.id == trackId) {
        return track.type;
      }
    }
    return null;
  }

  Future<void> _showTimelineToolsHelpDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Aide outils Timeline'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const <Widget>[
                  _TimelineToolHelpRow(
                    shortcut: 'V',
                    title: 'Selection',
                    description:
                        'Selectionne un clip pour le deplacer, le redimensionner ou l inspecter.',
                  ),
                  _TimelineToolHelpRow(
                    shortcut: 'B',
                    title: 'Lame (Blade)',
                    description:
                        'Active la coupe pour decouper un clip a la position du playhead.',
                  ),
                  _TimelineToolHelpRow(
                    shortcut: 'T',
                    title: 'Trim',
                    description:
                        'Ajuste precisement les points d entree/sortie d un clip.',
                  ),
                  _TimelineToolHelpRow(
                    shortcut: 'H',
                    title: 'Main (Pan)',
                    description:
                        'Deplace la vue de la timeline horizontalement.',
                  ),
                  _TimelineToolHelpRow(
                    shortcut: 'M',
                    title: 'Marqueur',
                    description:
                        'Place des reperes temporels pour organiser le montage.',
                  ),
                  _TimelineToolHelpRow(
                    shortcut: 'N',
                    title: 'Snap',
                    description:
                        'Active/desactive l aimantation des clips sur les bords et reperes.',
                  ),
                  _TimelineToolHelpRow(
                    shortcut: 'S',
                    title: 'Split',
                    description:
                        'Coupe le clip selectionne au niveau du playhead.',
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditTextDialog({
    required BuildContext context,
    required ProjectController projectController,
    required String trackId,
    required Clip clip,
  }) async {
    String draftText = clip.textContent?.trim().isNotEmpty == true
        ? clip.textContent!
        : 'Nouveau texte';
    final String? edited = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Editer texte'),
          content: TextFormField(
            initialValue: draftText,
            autofocus: true,
            maxLines: 3,
            onChanged: (String value) {
              draftText = value;
            },
            decoration: const InputDecoration(
              labelText: 'Texte affiche en preview',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(draftText.trim());
              },
              child: const Text('Appliquer'),
            ),
          ],
        );
      },
    );
    if (edited == null || edited.isEmpty) {
      return;
    }
    projectController.updateClipTextContent(
      trackId: trackId,
      clipId: clip.id,
      text: edited,
    );
  }

  Future<void> _showRenameTrackDialog({
    required BuildContext context,
    required ProjectController projectController,
    required Track track,
  }) async {
    String draftName = track.name?.trim().isNotEmpty == true
        ? track.name!
        : 'Texte ${track.index + 1}';
    final String? edited = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Renommer la piste texte'),
          content: TextFormField(
            initialValue: draftName,
            autofocus: true,
            maxLines: 1,
            onChanged: (String value) {
              draftName = value;
            },
            decoration: const InputDecoration(labelText: 'Nom de la piste'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(draftName.trim());
              },
              child: const Text('Appliquer'),
            ),
          ],
        );
      },
    );
    if (edited == null || edited.isEmpty) {
      return;
    }
    projectController.renameTrack(trackId: track.id, name: edited);
  }
}

class _ClipInspectorValues {
  const _ClipInspectorValues({
    required this.opacity,
    required this.speed,
    required this.volume,
    required this.scale,
    required this.rotationDeg,
    required this.textPosXPx,
    required this.textPosYPx,
    required this.textFontSizePx,
    required this.textFontFamily,
    required this.textBold,
    required this.textItalic,
    required this.textColorHex,
    required this.textBackgroundHex,
    required this.textEntryAnimation,
    required this.textExitAnimation,
    required this.textEntryFade,
    required this.textEntrySlideUp,
    required this.textEntrySlideDown,
    required this.textEntryZoom,
    required this.textExitFade,
    required this.textExitSlideUp,
    required this.textExitSlideDown,
    required this.textExitZoom,
    required this.textEntryDurationMs,
    required this.textExitDurationMs,
    required this.textEntryOffsetPx,
    required this.textExitOffsetPx,
    required this.textEntryScale,
    required this.textExitScale,
    required this.karaokeEnabled,
    required this.karaokeFillColorHex,
    required this.karaokeLeadInMs,
    required this.karaokeSweepDurationMs,
    required this.effectIntensity,
    bool? textShowBackground,
    bool? textShowBorder,
  }) : _textShowBackground = textShowBackground,
       _textShowBorder = textShowBorder;

  static const _ClipInspectorValues defaults = _ClipInspectorValues(
    opacity: 1.0,
    speed: 1.0,
    volume: 1.0,
    scale: 1.0,
    rotationDeg: 0.0,
    textPosXPx: 0.0,
    textPosYPx: 0.0,
    textFontSizePx: 42.0,
    textFontFamily: 'Roboto',
    textBold: false,
    textItalic: false,
    textColorHex: '#FFFFFF',
    textBackgroundHex: '#000000',
    textEntryAnimation: TextAnimationType.none,
    textExitAnimation: TextAnimationType.none,
    textEntryFade: false,
    textEntrySlideUp: false,
    textEntrySlideDown: false,
    textEntryZoom: false,
    textExitFade: false,
    textExitSlideUp: false,
    textExitSlideDown: false,
    textExitZoom: false,
    textEntryDurationMs: 300,
    textExitDurationMs: 300,
    textEntryOffsetPx: 28.0,
    textExitOffsetPx: 28.0,
    textEntryScale: 0.70,
    textExitScale: 0.70,
    karaokeEnabled: false,
    karaokeFillColorHex: '#FEE440',
    karaokeLeadInMs: 0,
    karaokeSweepDurationMs: 2500,
    effectIntensity: 0.6,
    textShowBackground: true,
    textShowBorder: true,
  );

  factory _ClipInspectorValues.fromClip(Clip clip) {
    return _ClipInspectorValues(
      opacity: clip.opacity,
      speed: clip.speed,
      volume: clip.volume,
      scale: clip.scale,
      rotationDeg: clip.rotationDeg,
      textPosXPx: clip.textPosXPx,
      textPosYPx: clip.textPosYPx,
      textFontSizePx: clip.textFontSizePx,
      textFontFamily: clip.textFontFamily,
      textBold: clip.textBold,
      textItalic: clip.textItalic,
      textColorHex: clip.textColorHex,
      textBackgroundHex: clip.textBackgroundHex,
      textEntryAnimation: clip.textEntryAnimation,
      textExitAnimation: clip.textExitAnimation,
      textEntryFade: clip.hasEntryFade,
      textEntrySlideUp: clip.hasEntrySlideUp,
      textEntrySlideDown: clip.hasEntrySlideDown,
      textEntryZoom: clip.hasEntryZoom,
      textExitFade: clip.hasExitFade,
      textExitSlideUp: clip.hasExitSlideUp,
      textExitSlideDown: clip.hasExitSlideDown,
      textExitZoom: clip.hasExitZoom,
      textEntryDurationMs: clip.textEntryDurationMs.toDouble(),
      textExitDurationMs: clip.textExitDurationMs.toDouble(),
      textEntryOffsetPx: clip.textEntryOffsetPx,
      textExitOffsetPx: clip.textExitOffsetPx,
      textEntryScale: clip.textEntryScale,
      textExitScale: clip.textExitScale,
      karaokeEnabled: clip.karaokeEnabled,
      karaokeFillColorHex: clip.karaokeFillColorHex,
      karaokeLeadInMs: clip.karaokeLeadInMs.toDouble(),
      karaokeSweepDurationMs: clip.karaokeSweepDurationMs.toDouble(),
      effectIntensity: clip.effectIntensity,
      textShowBackground: clip.textShowBackground,
      textShowBorder: clip.textShowBorder,
    );
  }

  final double opacity;
  final double speed;
  final double volume;
  final double scale;
  final double rotationDeg;
  final double textPosXPx;
  final double textPosYPx;
  final double textFontSizePx;
  final String textFontFamily;
  final bool textBold;
  final bool textItalic;
  final String textColorHex;
  final String textBackgroundHex;
  final TextAnimationType textEntryAnimation;
  final TextAnimationType textExitAnimation;
  final bool textEntryFade;
  final bool textEntrySlideUp;
  final bool textEntrySlideDown;
  final bool textEntryZoom;
  final bool textExitFade;
  final bool textExitSlideUp;
  final bool textExitSlideDown;
  final bool textExitZoom;
  final double textEntryDurationMs;
  final double textExitDurationMs;
  final double textEntryOffsetPx;
  final double textExitOffsetPx;
  final double textEntryScale;
  final double textExitScale;
  final bool karaokeEnabled;
  final String karaokeFillColorHex;
  final double karaokeLeadInMs;
  final double karaokeSweepDurationMs;
  final double effectIntensity;
  final bool? _textShowBackground;
  final bool? _textShowBorder;
  bool get textShowBackground => _textShowBackground ?? true;
  bool get textShowBorder => _textShowBorder ?? true;

  _ClipInspectorValues copyWith({
    double? opacity,
    double? speed,
    double? volume,
    double? scale,
    double? rotationDeg,
    double? textPosXPx,
    double? textPosYPx,
    double? textFontSizePx,
    String? textFontFamily,
    bool? textBold,
    bool? textItalic,
    String? textColorHex,
    String? textBackgroundHex,
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
    double? textEntryDurationMs,
    double? textExitDurationMs,
    double? textEntryOffsetPx,
    double? textExitOffsetPx,
    double? textEntryScale,
    double? textExitScale,
    bool? karaokeEnabled,
    String? karaokeFillColorHex,
    double? karaokeLeadInMs,
    double? karaokeSweepDurationMs,
    double? effectIntensity,
    bool? textShowBackground,
    bool? textShowBorder,
  }) {
    return _ClipInspectorValues(
      opacity: opacity ?? this.opacity,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      scale: scale ?? this.scale,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      textPosXPx: textPosXPx ?? this.textPosXPx,
      textPosYPx: textPosYPx ?? this.textPosYPx,
      textFontSizePx: textFontSizePx ?? this.textFontSizePx,
      textFontFamily: textFontFamily ?? this.textFontFamily,
      textBold: textBold ?? this.textBold,
      textItalic: textItalic ?? this.textItalic,
      textColorHex: textColorHex ?? this.textColorHex,
      textBackgroundHex: textBackgroundHex ?? this.textBackgroundHex,
      textEntryAnimation: textEntryAnimation ?? this.textEntryAnimation,
      textExitAnimation: textExitAnimation ?? this.textExitAnimation,
      textEntryFade: textEntryFade ?? this.textEntryFade,
      textEntrySlideUp: textEntrySlideUp ?? this.textEntrySlideUp,
      textEntrySlideDown: textEntrySlideDown ?? this.textEntrySlideDown,
      textEntryZoom: textEntryZoom ?? this.textEntryZoom,
      textExitFade: textExitFade ?? this.textExitFade,
      textExitSlideUp: textExitSlideUp ?? this.textExitSlideUp,
      textExitSlideDown: textExitSlideDown ?? this.textExitSlideDown,
      textExitZoom: textExitZoom ?? this.textExitZoom,
      textEntryDurationMs: textEntryDurationMs ?? this.textEntryDurationMs,
      textExitDurationMs: textExitDurationMs ?? this.textExitDurationMs,
      textEntryOffsetPx: textEntryOffsetPx ?? this.textEntryOffsetPx,
      textExitOffsetPx: textExitOffsetPx ?? this.textExitOffsetPx,
      textEntryScale: textEntryScale ?? this.textEntryScale,
      textExitScale: textExitScale ?? this.textExitScale,
      karaokeEnabled: karaokeEnabled ?? this.karaokeEnabled,
      karaokeFillColorHex: karaokeFillColorHex ?? this.karaokeFillColorHex,
      karaokeLeadInMs: karaokeLeadInMs ?? this.karaokeLeadInMs,
      karaokeSweepDurationMs:
          karaokeSweepDurationMs ?? this.karaokeSweepDurationMs,
      effectIntensity: effectIntensity ?? this.effectIntensity,
      textShowBackground: textShowBackground ?? this.textShowBackground,
      textShowBorder: textShowBorder ?? this.textShowBorder,
    );
  }
}

class _ClipInspectorCard extends StatelessWidget {
  const _ClipInspectorCard({
    required this.trackId,
    required this.trackType,
    required this.clip,
    required this.values,
    required this.onChanged,
    this.onEditText,
  });

  final String trackId;
  final TrackType trackType;
  final Clip clip;
  final _ClipInspectorValues values;
  final ValueChanged<_ClipInspectorValues> onChanged;
  final VoidCallback? onEditText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cyberpunk.border),
        color: context.cyberpunk.bgPrimary.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            trackType == TrackType.text
                ? (clip.textContent?.trim().isNotEmpty == true
                      ? clip.textContent!
                      : 'Texte')
                : (trackType == TrackType.visualEffect ||
                          trackType == TrackType.audioEffect
                      ? _effectLabelForClip(trackType, clip)
                      : clip.assetPath.split('/').last),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.cyberpunk.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Track: $trackId',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.cyberpunk.textMuted),
          ),
          const SizedBox(height: 6),
          if (trackType == TrackType.text) ...<Widget>[
            _TextInspectorSection(
              values: values,
              onChanged: onChanged,
              onEditText: onEditText,
            ),
            Divider(color: context.cyberpunk.border.withValues(alpha: 0.7)),
          ],
          if (trackType == TrackType.visualEffect ||
              trackType == TrackType.audioEffect) ...<Widget>[
            Text(
              trackType == TrackType.visualEffect
                  ? 'Effet visuel'
                  : 'Effet sonore',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.cyberpunk.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _effectLabelForClip(trackType, clip),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.cyberpunk.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            _InspectorSlider(
              label:
                  'Intensite ${(values.effectIntensity * 100).toStringAsFixed(0)}%',
              min: 0.1,
              max: 1.0,
              value: values.effectIntensity,
              activeColor: context.cyberpunk.neonBlue,
              onChanged: (double value) {
                onChanged(values.copyWith(effectIntensity: value));
              },
            ),
            Divider(color: context.cyberpunk.border.withValues(alpha: 0.7)),
          ],
          if (trackType == TrackType.video || trackType == TrackType.overlay)
            ...<Widget>[
            Text(
              'Transform',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.cyberpunk.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            _InspectorSlider(
              label: 'Scale ${values.scale.toStringAsFixed(2)}x',
              min: 0.5,
              max: 2.0,
              value: values.scale,
              activeColor: context.cyberpunk.neonBlue,
              onChanged: (double value) {
                onChanged(values.copyWith(scale: value));
              },
            ),
            _InspectorSlider(
              label: 'Rotation ${values.rotationDeg.toStringAsFixed(0)}deg',
              min: -180,
              max: 180,
              value: values.rotationDeg,
              activeColor: context.cyberpunk.neonBlue,
              onChanged: (double value) {
                onChanged(values.copyWith(rotationDeg: value));
              },
            ),
            Divider(color: context.cyberpunk.border.withValues(alpha: 0.7)),
          ],
          if (trackType == TrackType.video || trackType == TrackType.overlay)
            ...<Widget>[
            Text(
              'Image / Video',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.cyberpunk.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            _InspectorSlider(
              label: 'Opacite ${(values.opacity * 100).round()}%',
              min: 0,
              max: 1,
              value: values.opacity,
              activeColor: context.cyberpunk.neonBlue,
              onChanged: (double value) {
                onChanged(values.copyWith(opacity: value));
              },
            ),
          ],
          if (trackType == TrackType.audio ||
              trackType == TrackType.video ||
              trackType == TrackType.overlay) ...<Widget>[
            Divider(color: context.cyberpunk.border.withValues(alpha: 0.7)),
            Text(
              'Audio / Tempo',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.cyberpunk.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            _InspectorSlider(
              label: 'Vitesse ${values.speed.toStringAsFixed(2)}x',
              min: 0.25,
              max: 2.0,
              value: values.speed,
              activeColor: context.cyberpunk.neonPink,
              onChanged: (double value) {
                onChanged(values.copyWith(speed: value));
              },
            ),
            _InspectorSlider(
              label: 'Volume ${(values.volume * 100).round()}%',
              min: 0,
              max: 2.0,
              value: values.volume,
              activeColor: context.cyberpunk.neonPink,
              onChanged: (double value) {
                onChanged(values.copyWith(volume: value));
              },
            ),
          ],
        ],
      ),
    );
  }

  String _effectLabelForClip(TrackType type, Clip clip) {
    if (type == TrackType.visualEffect) {
      switch (clip.visualEffectType) {
        case VisualEffectType.glitch:
          return 'Glitch cyberpunk';
        case VisualEffectType.shake:
          return 'Tremblement';
        case VisualEffectType.rgbSplit:
          return 'RGB Split';
        case VisualEffectType.flash:
          return 'Flash';
        case VisualEffectType.vhs:
          return 'VHS';
        case null:
          return 'Effet visuel';
      }
    }
    switch (clip.audioEffectType) {
      case AudioEffectType.censorBeep:
        return 'Bip censure';
      case AudioEffectType.distortion:
        return 'Distorsion';
      case AudioEffectType.stutter:
        return 'Stutter';
      case null:
        return 'Effet sonore';
    }
  }
}

class _TextInspectorSection extends StatefulWidget {
  const _TextInspectorSection({
    required this.values,
    required this.onChanged,
    this.onEditText,
  });

  final _ClipInspectorValues values;
  final ValueChanged<_ClipInspectorValues> onChanged;
  final VoidCallback? onEditText;

  @override
  State<_TextInspectorSection> createState() => _TextInspectorSectionState();
}

class _TextInspectorSectionState extends State<_TextInspectorSection> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final _ClipInspectorValues values = widget.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Texte (rich text v1)',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.cyberpunk.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(
              value: 0,
              icon: Icon(Icons.text_fields_outlined),
              label: Text('Texte'),
            ),
            ButtonSegment<int>(
              value: 1,
              icon: Icon(Icons.animation_outlined),
              label: Text('Animation'),
            ),
          ],
          selected: <int>{_tabIndex},
          onSelectionChanged: (Set<int> selection) {
            setState(() {
              _tabIndex = selection.first;
            });
          },
        ),
        const SizedBox(height: 8),
        if (_tabIndex == 0) ...<Widget>[
          FilledButton.icon(
            onPressed: widget.onEditText,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editer texte'),
          ),
          _InspectorSlider(
            label: 'Position X ${values.textPosXPx.toStringAsFixed(0)} px',
            min: -900,
            max: 900,
            value: values.textPosXPx,
            activeColor: context.cyberpunk.neonBlue,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(textPosXPx: value));
            },
          ),
          _InspectorSlider(
            label: 'Position Y ${values.textPosYPx.toStringAsFixed(0)} px',
            min: -500,
            max: 500,
            value: values.textPosYPx,
            activeColor: context.cyberpunk.neonBlue,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(textPosYPx: value));
            },
          ),
          _InspectorSlider(
            label: 'Angle ${values.rotationDeg.toStringAsFixed(0)}deg',
            min: -180,
            max: 180,
            value: values.rotationDeg,
            activeColor: context.cyberpunk.neonBlue,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(rotationDeg: value));
            },
          ),
          _InspectorSlider(
            label:
                'Taille police ${values.textFontSizePx.toStringAsFixed(0)} px',
            min: 12,
            max: 160,
            value: values.textFontSizePx,
            activeColor: context.cyberpunk.neonPink,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(textFontSizePx: value));
            },
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: values.textFontFamily,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Police',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items:
                const <String>[
                      'Roboto',
                      'Arial',
                      'Helvetica',
                      'Avenir Next',
                      'Futura',
                      'Georgia',
                      'Menlo',
                      'Times New Roman',
                      'Courier New',
                    ]
                    .map((String family) {
                      return DropdownMenuItem<String>(
                        value: family,
                        child: Text(family),
                      );
                    })
                    .toList(growable: false),
            onChanged: (String? family) {
              if (family == null) {
                return;
              }
              widget.onChanged(values.copyWith(textFontFamily: family));
            },
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            value: values.karaokeEnabled,
            onChanged: (bool enabled) {
              widget.onChanged(values.copyWith(karaokeEnabled: enabled));
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Mode karaoke'),
            subtitle: const Text(
              'Remplissage lineaire progressif gauche -> droite',
            ),
          ),
          _ColorChoiceRow(
            label: 'Couleur remplissage karaoke',
            selectedHex: values.karaokeFillColorHex,
            choices: const <String>[
              '#FEE440',
              '#FF9E00',
              '#00E5FF',
              '#FF4FB0',
              '#A3E635',
            ],
            onSelect: (String hex) {
              widget.onChanged(values.copyWith(karaokeFillColorHex: hex));
            },
          ),
          _InspectorSlider(
            label:
                'Delai depart karaoke ${values.karaokeLeadInMs.toStringAsFixed(0)} ms',
            min: 0,
            max: 3000,
            value: values.karaokeLeadInMs,
            activeColor: context.cyberpunk.neonBlue,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(karaokeLeadInMs: value));
            },
          ),
          _InspectorSlider(
            label:
                'Duree sweep karaoke ${values.karaokeSweepDurationMs.toStringAsFixed(0)} ms',
            min: 300,
            max: 10000,
            value: values.karaokeSweepDurationMs,
            activeColor: context.cyberpunk.neonPink,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(karaokeSweepDurationMs: value));
            },
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              FilterChip(
                label: const Text('Gras'),
                selected: values.textBold,
                onSelected: (bool selected) {
                  widget.onChanged(values.copyWith(textBold: selected));
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Italique'),
                selected: values.textItalic,
                onSelected: (bool selected) {
                  widget.onChanged(values.copyWith(textItalic: selected));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              FilterChip(
                label: const Text('Fond'),
                selected: values.textShowBackground,
                onSelected: (bool selected) {
                  widget.onChanged(
                    values.copyWith(textShowBackground: selected),
                  );
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Bordure'),
                selected: values.textShowBorder,
                onSelected: (bool selected) {
                  widget.onChanged(values.copyWith(textShowBorder: selected));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          _ColorChoiceRow(
            label: 'Couleur texte',
            selectedHex: values.textColorHex,
            choices: const <String>[
              '#FFFFFF',
              '#FEE440',
              '#FF9E00',
              '#00E5FF',
              '#FF4FB0',
            ],
            onSelect: (String hex) {
              widget.onChanged(values.copyWith(textColorHex: hex));
            },
          ),
          const SizedBox(height: 4),
          _ColorChoiceRow(
            label: 'Fond texte',
            selectedHex: values.textBackgroundHex,
            choices: const <String>[
              '#000000',
              '#1A1A1A',
              '#1F2937',
              '#4A044E',
              '#002B36',
            ],
            onSelect: (String hex) {
              widget.onChanged(values.copyWith(textBackgroundHex: hex));
            },
          ),
        ] else ...<Widget>[
          _TextAnimationMiniTimeline(values: values),
          const SizedBox(height: 8),
          Text(
            'Apparition (effets cumulables)',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.cyberpunk.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('Fondu'),
                selected: values.textEntryFade,
                onSelected: (bool selected) {
                  widget.onChanged(values.copyWith(textEntryFade: selected));
                },
              ),
              FilterChip(
                label: const Text('Slide haut'),
                selected: values.textEntrySlideUp,
                onSelected: (bool selected) {
                  widget.onChanged(values.copyWith(textEntrySlideUp: selected));
                },
              ),
              FilterChip(
                label: const Text('Slide bas'),
                selected: values.textEntrySlideDown,
                onSelected: (bool selected) {
                  widget.onChanged(
                    values.copyWith(textEntrySlideDown: selected),
                  );
                },
              ),
              FilterChip(
                label: const Text('Zoom'),
                selected: values.textEntryZoom,
                onSelected: (bool selected) {
                  widget.onChanged(values.copyWith(textEntryZoom: selected));
                },
              ),
            ],
          ),
          _InspectorSlider(
            label:
                'Duree apparition ${values.textEntryDurationMs.toStringAsFixed(0)} ms',
            min: 0,
            max: 3000,
            value: values.textEntryDurationMs,
            activeColor: context.cyberpunk.neonBlue,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(textEntryDurationMs: value));
            },
          ),
          _InspectorSlider(
            label:
                'Offset apparition ${values.textEntryOffsetPx.toStringAsFixed(0)} px',
            min: 0,
            max: 180,
            value: values.textEntryOffsetPx,
            activeColor: context.cyberpunk.neonBlue,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(textEntryOffsetPx: value));
            },
          ),
          _InspectorSlider(
            label:
                'Zoom apparition ${(values.textEntryScale * 100).toStringAsFixed(0)}%',
            min: 0.2,
            max: 1.0,
            value: values.textEntryScale,
            activeColor: context.cyberpunk.neonBlue,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(textEntryScale: value));
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Sortie (effets cumulables)',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.cyberpunk.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('Fondu'),
                selected: values.textExitFade,
                onSelected: (bool selected) {
                  widget.onChanged(values.copyWith(textExitFade: selected));
                },
              ),
              FilterChip(
                label: const Text('Slide haut'),
                selected: values.textExitSlideUp,
                onSelected: (bool selected) {
                  widget.onChanged(values.copyWith(textExitSlideUp: selected));
                },
              ),
              FilterChip(
                label: const Text('Slide bas'),
                selected: values.textExitSlideDown,
                onSelected: (bool selected) {
                  widget.onChanged(
                    values.copyWith(textExitSlideDown: selected),
                  );
                },
              ),
              FilterChip(
                label: const Text('Zoom'),
                selected: values.textExitZoom,
                onSelected: (bool selected) {
                  widget.onChanged(values.copyWith(textExitZoom: selected));
                },
              ),
            ],
          ),
          _InspectorSlider(
            label:
                'Duree sortie ${values.textExitDurationMs.toStringAsFixed(0)} ms',
            min: 0,
            max: 3000,
            value: values.textExitDurationMs,
            activeColor: context.cyberpunk.neonPink,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(textExitDurationMs: value));
            },
          ),
          _InspectorSlider(
            label:
                'Offset sortie ${values.textExitOffsetPx.toStringAsFixed(0)} px',
            min: 0,
            max: 180,
            value: values.textExitOffsetPx,
            activeColor: context.cyberpunk.neonPink,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(textExitOffsetPx: value));
            },
          ),
          _InspectorSlider(
            label:
                'Zoom sortie ${(values.textExitScale * 100).toStringAsFixed(0)}%',
            min: 0.2,
            max: 1.0,
            value: values.textExitScale,
            activeColor: context.cyberpunk.neonPink,
            onChanged: (double value) {
              widget.onChanged(values.copyWith(textExitScale: value));
            },
          ),
        ],
      ],
    );
  }
}

class _TextAnimationMiniTimeline extends StatelessWidget {
  const _TextAnimationMiniTimeline({required this.values});

  final _ClipInspectorValues values;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cyberpunk.border),
        color: context.cyberpunk.bgPrimary.withValues(alpha: 0.22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Courbe animation entree/sortie',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.cyberpunk.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: CustomPaint(
              painter: _TextAnimationMiniTimelinePainter(
                values: values,
                border: context.cyberpunk.border,
                entryColor: context.cyberpunk.neonBlue,
                exitColor: context.cyberpunk.neonPink,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextAnimationMiniTimelinePainter extends CustomPainter {
  const _TextAnimationMiniTimelinePainter({
    required this.values,
    required this.border,
    required this.entryColor,
    required this.exitColor,
  });

  final _ClipInspectorValues values;
  final Color border;
  final Color entryColor;
  final Color exitColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final Rect rect = Offset.zero & size;
    final Paint grid = Paint()
      ..color = border.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    final Paint centerLine = Paint()
      ..color = border.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;

    for (int i = 1; i <= 3; i++) {
      final double x = rect.left + rect.width * (i / 4);
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
    }
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      centerLine,
    );

    const double referenceMs = 6000;
    final double entryFrac = (values.textEntryDurationMs / referenceMs).clamp(
      0.0,
      0.45,
    );
    final double exitFrac = (values.textExitDurationMs / referenceMs).clamp(
      0.0,
      0.45,
    );

    if (entryFrac > 0) {
      final Paint entryZone = Paint()
        ..color = entryColor.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width * entryFrac, rect.height),
        entryZone,
      );
    }
    if (exitFrac > 0) {
      final Paint exitZone = Paint()
        ..color = exitColor.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      final double zoneWidth = rect.width * exitFrac;
      canvas.drawRect(
        Rect.fromLTWH(rect.right - zoneWidth, rect.top, zoneWidth, rect.height),
        exitZone,
      );
    }

    final Path entryPath = Path();
    final Path exitPath = Path();
    for (int i = 0; i <= 100; i++) {
      final double t = i / 100;
      final double x = rect.left + rect.width * t;
      final double entryValue = _entryCurveValue(t, entryFrac);
      final double exitValue = _exitCurveValue(t, exitFrac);
      final double entryY = rect.bottom - (rect.height * entryValue);
      final double exitY = rect.bottom - (rect.height * exitValue);
      if (i == 0) {
        entryPath.moveTo(x, entryY);
        exitPath.moveTo(x, exitY);
      } else {
        entryPath.lineTo(x, entryY);
        exitPath.lineTo(x, exitY);
      }
    }

    canvas.drawPath(
      entryPath,
      Paint()
        ..color = entryColor.withValues(alpha: 0.9)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      exitPath,
      Paint()
        ..color = exitColor.withValues(alpha: 0.85)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
  }

  double _entryCurveValue(double t, double entryFrac) {
    final bool hasEntryAnim =
        values.textEntryFade ||
        values.textEntrySlideUp ||
        values.textEntrySlideDown ||
        values.textEntryZoom;
    if (entryFrac <= 0 || !hasEntryAnim) {
      return 1.0;
    }
    if (t > entryFrac) {
      return 1.0;
    }
    final double p = (t / entryFrac).clamp(0.0, 1.0);
    if (values.textEntryFade) {
      return p;
    }
    if (values.textEntryZoom) {
      return values.textEntryScale + (1 - values.textEntryScale) * p;
    }
    return Curves.easeOut.transform(p);
  }

  double _exitCurveValue(double t, double exitFrac) {
    final bool hasExitAnim =
        values.textExitFade ||
        values.textExitSlideUp ||
        values.textExitSlideDown ||
        values.textExitZoom;
    if (exitFrac <= 0 || !hasExitAnim) {
      return 1.0;
    }
    final double start = 1 - exitFrac;
    if (t < start) {
      return 1.0;
    }
    final double p = ((t - start) / exitFrac).clamp(0.0, 1.0);
    if (values.textExitFade) {
      return 1 - p;
    }
    if (values.textExitZoom) {
      return 1 - (1 - values.textExitScale) * p;
    }
    return 1 - Curves.easeIn.transform(p);
  }

  @override
  bool shouldRepaint(covariant _TextAnimationMiniTimelinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.border != border ||
        oldDelegate.entryColor != entryColor ||
        oldDelegate.exitColor != exitColor;
  }
}

class _InspectorSlider extends StatelessWidget {
  const _InspectorSlider({
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  final String label;
  final double min;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.cyberpunk.textMuted),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor:
                activeColor ?? Theme.of(context).colorScheme.primary,
            thumbColor: activeColor ?? Theme.of(context).colorScheme.primary,
          ),
          child: Slider(
            min: min,
            max: max,
            value: value.clamp(min, max),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ColorChoiceRow extends StatelessWidget {
  const _ColorChoiceRow({
    required this.label,
    required this.selectedHex,
    required this.choices,
    required this.onSelect,
  });

  final String label;
  final String selectedHex;
  final List<String> choices;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.cyberpunk.textMuted),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: choices
              .map((String hex) {
                final bool selected = selectedHex == hex;
                return GestureDetector(
                  onTap: () => onSelect(hex),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _colorFromHex(hex),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? context.cyberpunk.neonBlue
                            : context.cyberpunk.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }

  Color _colorFromHex(String hex) {
    final String normalized = hex.replaceAll('#', '').trim();
    if (normalized.length != 6) {
      return Colors.white;
    }
    final int? rgb = int.tryParse(normalized, radix: 16);
    if (rgb == null) {
      return Colors.white;
    }
    return Color(0xFF000000 | rgb);
  }
}

class _MediaToolsTabs extends StatefulWidget {
  const _MediaToolsTabs({
    required this.project,
    required this.mediaChild,
    required this.onAddTextAtPlayhead,
    required this.onAddVisualEffectAtPlayhead,
    required this.onAddAudioEffectAtPlayhead,
  });

  final Project? project;
  final Widget mediaChild;
  final void Function({String? targetTrackId, bool createNewTrack})?
  onAddTextAtPlayhead;
  final void Function({
    required VisualEffectType effectType,
    String? targetTrackId,
    bool createNewTrack,
  })?
  onAddVisualEffectAtPlayhead;
  final void Function({
    required AudioEffectType effectType,
    String? targetTrackId,
    bool createNewTrack,
  })?
  onAddAudioEffectAtPlayhead;

  @override
  State<_MediaToolsTabs> createState() => _MediaToolsTabsState();
}

class _MediaToolsTabsState extends State<_MediaToolsTabs> {
  String _activeTool = 'text';
  String _effectsCategory = 'visual';
  static const String _latestTextTrack = '__latest_text_track__';
  static const String _newTextTrack = '__new_text_track__';
  static const String _latestVisualTrack = '__latest_visual_track__';
  static const String _newVisualTrack = '__new_visual_track__';
  static const String _latestAudioEffectTrack = '__latest_audio_effect_track__';
  static const String _newAudioEffectTrack = '__new_audio_effect_track__';
  String _textTarget = _latestTextTrack;
  String _visualEffectTarget = _latestVisualTrack;
  String _audioEffectTarget = _latestAudioEffectTrack;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          TabBar(
            tabs: const <Tab>[
              Tab(text: 'Media'),
              Tab(text: 'Outils'),
            ],
            labelColor: context.cyberpunk.neonBlue,
            unselectedLabelColor: context.cyberpunk.textMuted,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                widget.mediaChild,
                ListView(
                  children: <Widget>[
                    Text(
                      'Bibliotheque outils',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _SquareToolButton(
                          icon: Icons.text_fields,
                          label: 'Texte',
                          isSelected: _activeTool == 'text',
                          onTap: () => setState(() => _activeTool = 'text'),
                        ),
                        _SquareToolButton(
                          icon: Icons.auto_awesome,
                          label: 'Effets',
                          isSelected: _activeTool == 'effects',
                          onTap: () => setState(() => _activeTool = 'effects'),
                        ),
                        _SquareToolButton(
                          icon: Icons.movie_filter_outlined,
                          label: 'Transitions',
                          isSelected: _activeTool == 'transitions',
                          onTap: () =>
                              setState(() => _activeTool = 'transitions'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: _buildToolPanel(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolPanel(BuildContext context) {
    if (_activeTool == 'text') {
      final List<Track> textTracks =
          (widget.project?.tracks ?? const <Track>[])
              .where((Track track) => track.type == TrackType.text)
              .toList(growable: false)
            ..sort((Track a, Track b) => a.index.compareTo(b.index));
      return Container(
        key: const ValueKey<String>('tool_text'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.cyberpunk.border),
          color: context.cyberpunk.bgPrimary.withValues(alpha: 0.35),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Texte', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Ajoute un clip texte sur la timeline a la tete de lecture. Tu peux cibler la piste texte existante ou creer une nouvelle source.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.cyberpunk.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _textTarget,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Destination texte',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: _latestTextTrack,
                  child: Text(
                    'Piste texte active (derniere)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...textTracks.map((Track track) {
                  final String trackLabel =
                      track.name?.trim().isNotEmpty == true
                      ? track.name!
                      : 'Piste texte ${track.index + 1}';
                  return DropdownMenuItem<String>(
                    value: track.id,
                    child: Text(
                      trackLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
                const DropdownMenuItem<String>(
                  value: _newTextTrack,
                  child: Text(
                    'Nouvelle piste texte',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _textTarget = value;
                });
              },
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: widget.onAddTextAtPlayhead == null
                  ? null
                  : () {
                      widget.onAddTextAtPlayhead!(
                        targetTrackId:
                            _textTarget == _latestTextTrack ||
                                _textTarget == _newTextTrack
                            ? null
                            : _textTarget,
                        createNewTrack: _textTarget == _newTextTrack,
                      );
                    },
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Ajouter texte au playhead'),
            ),
          ],
        ),
      );
    }

    if (_activeTool == 'effects') {
      return _buildEffectsPanel(context);
    }

    final String title = 'Transitions';
    return Container(
      key: ValueKey<String>('tool_$_activeTool'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cyberpunk.border),
        color: context.cyberpunk.bgPrimary.withValues(alpha: 0.35),
      ),
      child: Text(
        '$title: bientot disponible (module en preparation).',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.cyberpunk.textMuted),
      ),
    );
  }

  Widget _buildEffectsPanel(BuildContext context) {
    final List<Track> visualTracks =
        (widget.project?.tracks ?? const <Track>[])
            .where((Track track) => track.type == TrackType.visualEffect)
            .toList(growable: false)
          ..sort((Track a, Track b) => a.index.compareTo(b.index));
    final List<Track> audioTracks =
        (widget.project?.tracks ?? const <Track>[])
            .where((Track track) => track.type == TrackType.audioEffect)
            .toList(growable: false)
          ..sort((Track a, Track b) => a.index.compareTo(b.index));

    return Container(
      key: const ValueKey<String>('tool_effects'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cyberpunk.border),
        color: context.cyberpunk.bgPrimary.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Effets', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'visual',
                icon: Icon(Icons.auto_awesome_outlined),
                label: Text('Visuels'),
              ),
              ButtonSegment<String>(
                value: 'audio',
                icon: Icon(Icons.graphic_eq),
                label: Text('Sonores'),
              ),
            ],
            selected: <String>{_effectsCategory},
            onSelectionChanged: (Set<String> selection) {
              setState(() {
                _effectsCategory = selection.first;
              });
            },
          ),
          const SizedBox(height: 8),
          if (_effectsCategory == 'visual') ...<Widget>[
            _effectTrackDropdown(
              context: context,
              label: 'Destination effets visuels',
              currentValue: _visualEffectTarget,
              latestValue: _latestVisualTrack,
              newValue: _newVisualTrack,
              latestLabel: 'Piste effets visuels active',
              newLabel: 'Nouvelle piste effets visuels',
              tracks: visualTracks,
              trackLabelBuilder: _visualTrackLabel,
              onChanged: (String value) {
                setState(() {
                  _visualEffectTarget = value;
                });
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _effectAddButton(
                  label: 'Glitch',
                  icon: Icons.bolt_outlined,
                  onTap: widget.onAddVisualEffectAtPlayhead == null
                      ? null
                      : () => widget.onAddVisualEffectAtPlayhead!(
                          effectType: VisualEffectType.glitch,
                          targetTrackId:
                              _visualEffectTarget == _latestVisualTrack ||
                                  _visualEffectTarget == _newVisualTrack
                              ? null
                              : _visualEffectTarget,
                          createNewTrack:
                              _visualEffectTarget == _newVisualTrack,
                        ),
                ),
                _effectAddButton(
                  label: 'Tremblement',
                  icon: Icons.vibration_outlined,
                  onTap: widget.onAddVisualEffectAtPlayhead == null
                      ? null
                      : () => widget.onAddVisualEffectAtPlayhead!(
                          effectType: VisualEffectType.shake,
                          targetTrackId:
                              _visualEffectTarget == _latestVisualTrack ||
                                  _visualEffectTarget == _newVisualTrack
                              ? null
                              : _visualEffectTarget,
                          createNewTrack:
                              _visualEffectTarget == _newVisualTrack,
                        ),
                ),
                _effectAddButton(
                  label: 'RGB Split',
                  icon: Icons.blur_linear,
                  onTap: widget.onAddVisualEffectAtPlayhead == null
                      ? null
                      : () => widget.onAddVisualEffectAtPlayhead!(
                          effectType: VisualEffectType.rgbSplit,
                          targetTrackId:
                              _visualEffectTarget == _latestVisualTrack ||
                                  _visualEffectTarget == _newVisualTrack
                              ? null
                              : _visualEffectTarget,
                          createNewTrack:
                              _visualEffectTarget == _newVisualTrack,
                        ),
                ),
                _effectAddButton(
                  label: 'Flash',
                  icon: Icons.flash_on_outlined,
                  onTap: widget.onAddVisualEffectAtPlayhead == null
                      ? null
                      : () => widget.onAddVisualEffectAtPlayhead!(
                          effectType: VisualEffectType.flash,
                          targetTrackId:
                              _visualEffectTarget == _latestVisualTrack ||
                                  _visualEffectTarget == _newVisualTrack
                              ? null
                              : _visualEffectTarget,
                          createNewTrack:
                              _visualEffectTarget == _newVisualTrack,
                        ),
                ),
                _effectAddButton(
                  label: 'VHS',
                  icon: Icons.tv,
                  onTap: widget.onAddVisualEffectAtPlayhead == null
                      ? null
                      : () => widget.onAddVisualEffectAtPlayhead!(
                          effectType: VisualEffectType.vhs,
                          targetTrackId:
                              _visualEffectTarget == _latestVisualTrack ||
                                  _visualEffectTarget == _newVisualTrack
                              ? null
                              : _visualEffectTarget,
                          createNewTrack:
                              _visualEffectTarget == _newVisualTrack,
                        ),
                ),
              ],
            ),
          ] else ...<Widget>[
            _effectTrackDropdown(
              context: context,
              label: 'Destination effets sonores',
              currentValue: _audioEffectTarget,
              latestValue: _latestAudioEffectTrack,
              newValue: _newAudioEffectTrack,
              latestLabel: 'Piste effets sonores active',
              newLabel: 'Nouvelle piste effets sonores',
              tracks: audioTracks,
              trackLabelBuilder: _audioTrackLabel,
              onChanged: (String value) {
                setState(() {
                  _audioEffectTarget = value;
                });
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _effectAddButton(
                  label: 'Bip censure',
                  icon: Icons.volume_up_outlined,
                  onTap: widget.onAddAudioEffectAtPlayhead == null
                      ? null
                      : () => widget.onAddAudioEffectAtPlayhead!(
                          effectType: AudioEffectType.censorBeep,
                          targetTrackId:
                              _audioEffectTarget == _latestAudioEffectTrack ||
                                  _audioEffectTarget == _newAudioEffectTrack
                              ? null
                              : _audioEffectTarget,
                          createNewTrack:
                              _audioEffectTarget == _newAudioEffectTrack,
                        ),
                ),
                _effectAddButton(
                  label: 'Distorsion',
                  icon: Icons.multitrack_audio_outlined,
                  onTap: widget.onAddAudioEffectAtPlayhead == null
                      ? null
                      : () => widget.onAddAudioEffectAtPlayhead!(
                          effectType: AudioEffectType.distortion,
                          targetTrackId:
                              _audioEffectTarget == _latestAudioEffectTrack ||
                                  _audioEffectTarget == _newAudioEffectTrack
                              ? null
                              : _audioEffectTarget,
                          createNewTrack:
                              _audioEffectTarget == _newAudioEffectTrack,
                        ),
                ),
                _effectAddButton(
                  label: 'Stutter',
                  icon: Icons.graphic_eq,
                  onTap: widget.onAddAudioEffectAtPlayhead == null
                      ? null
                      : () => widget.onAddAudioEffectAtPlayhead!(
                          effectType: AudioEffectType.stutter,
                          targetTrackId:
                              _audioEffectTarget == _latestAudioEffectTrack ||
                                  _audioEffectTarget == _newAudioEffectTrack
                              ? null
                              : _audioEffectTarget,
                          createNewTrack:
                              _audioEffectTarget == _newAudioEffectTrack,
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _effectTrackDropdown({
    required BuildContext context,
    required String label,
    required String currentValue,
    required String latestValue,
    required String newValue,
    required String latestLabel,
    required String newLabel,
    required List<Track> tracks,
    required String Function(Track track) trackLabelBuilder,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(value: latestValue, child: Text(latestLabel)),
        ...tracks.map((Track track) {
          return DropdownMenuItem<String>(
            value: track.id,
            child: Text(
              trackLabelBuilder(track),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
        DropdownMenuItem<String>(value: newValue, child: Text(newLabel)),
      ],
      onChanged: (String? value) {
        if (value == null) {
          return;
        }
        onChanged(value);
      },
    );
  }

  Widget _effectAddButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  String _visualTrackLabel(Track track) {
    if (track.name?.trim().isNotEmpty == true) {
      return track.name!;
    }
    return 'Effets visuels ${track.index + 1}';
  }

  String _audioTrackLabel(Track track) {
    if (track.name?.trim().isNotEmpty == true) {
      return track.name!;
    }
    return 'Effets sonores ${track.index + 1}';
  }
}

class _SquareToolButton extends StatelessWidget {
  const _SquareToolButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? context.cyberpunk.neonBlue
                : context.cyberpunk.border,
          ),
          color: isSelected
              ? context.cyberpunk.neonBlue.withValues(alpha: 0.14)
              : context.cyberpunk.bgPrimary.withValues(alpha: 0.28),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? context.cyberpunk.neonBlue
                  : context.cyberpunk.textPrimary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.cyberpunk.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorExportTabs extends StatelessWidget {
  const _InspectorExportTabs({
    required this.project,
    required this.previewState,
    required this.projectState,
    required this.exportState,
    required this.runningExportJob,
    required this.queuedExportsCount,
    required this.inspectedTrackId,
    required this.inspectedTrackType,
    required this.inspectedClip,
    required this.inspectorByClipId,
    required this.previewGuidesEnabled,
    required this.onSelectPreset,
    required this.onEnqueueExport,
    required this.onCancelRunningExport,
    required this.statusLabelBuilder,
    required this.statusColorBuilder,
    required this.onInspectorChanged,
    required this.onEditText,
    required this.onTogglePreviewGuides,
  });

  final Project? project;
  final PreviewState previewState;
  final ProjectState projectState;
  final ExportQueueState exportState;
  final ExportJob? runningExportJob;
  final int queuedExportsCount;
  final String? inspectedTrackId;
  final TrackType? inspectedTrackType;
  final Clip? inspectedClip;
  final Map<String, _ClipInspectorValues> inspectorByClipId;
  final bool previewGuidesEnabled;
  final ValueChanged<ExportPreset> onSelectPreset;
  final VoidCallback? onEnqueueExport;
  final VoidCallback onCancelRunningExport;
  final String Function(ExportJobStatus status) statusLabelBuilder;
  final Color Function(BuildContext context, ExportJobStatus status)
  statusColorBuilder;
  final ValueChanged<_ClipInspectorValues> onInspectorChanged;
  final VoidCallback? onEditText;
  final ValueChanged<bool> onTogglePreviewGuides;

  void _copyToClipboard(BuildContext context, String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: trimmed));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Message d erreur copie')));
  }

  void _openExportInFinder(String outputPath) {
    final List<String> args = Platform.isMacOS
        ? <String>['-R', outputPath]
        : <String>[outputPath];
    unawaited(Process.run('open', args));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          TabBar(
            tabs: const <Tab>[
              Tab(text: 'Inspecteur'),
              Tab(text: 'Export'),
            ],
            labelColor: context.cyberpunk.neonBlue,
            unselectedLabelColor: context.cyberpunk.textMuted,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                ListView(
                  children: <Widget>[
                    Text(
                      'Inspecteur clip',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    if (inspectedClip == null)
                      Text(
                        'Selectionne un clip dans la timeline.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.cyberpunk.textMuted,
                        ),
                      )
                    else
                      _ClipInspectorCard(
                        trackId: inspectedTrackId ?? '-',
                        trackType: inspectedTrackType ?? TrackType.video,
                        clip: inspectedClip!,
                        values:
                            inspectorByClipId[inspectedClip!.id] ??
                            _ClipInspectorValues.fromClip(inspectedClip!),
                        onChanged: onInspectorChanged,
                        onEditText: onEditText,
                      ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: previewGuidesEnabled,
                      onChanged: onTogglePreviewGuides,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Grille de reperes preview'),
                      subtitle: const Text(
                        'Repere visuel 3x3 pour le placement',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Projet',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      project == null
                          ? 'Aucun projet actif'
                          : '${project!.name}\n${project!.canvasWidth}x${project!.canvasHeight} - ${project!.fps} fps',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (projectState.projectFilePath != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        projectState.projectFilePath!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.cyberpunk.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
                ListView(
                  children: <Widget>[
                    Text(
                      'Preset export',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ExportPreset>(
                      initialValue: exportState.selectedPreset,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Preset',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ExportPreset.defaults
                          .map(
                            (ExportPreset preset) => DropdownMenuItem(
                              value: preset,
                              child: Text(preset.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (ExportPreset? preset) {
                        if (preset == null) {
                          return;
                        }
                        onSelectPreset(preset);
                      },
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: onEnqueueExport,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(
                        exportState.isProcessing
                            ? 'Export en cours...'
                            : 'Ajouter a la queue',
                      ),
                    ),
                    if (exportState.isProcessing) ...<Widget>[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.cyberpunk.neonBlue.withValues(
                              alpha: 0.55,
                            ),
                          ),
                          color: context.cyberpunk.neonBlue.withValues(
                            alpha: 0.08,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    runningExportJob == null
                                        ? 'Traitement de la queue export...'
                                        : 'Export en cours: ${runningExportJob!.presetLabel}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: context.cyberpunk.neonBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: (runningExportJob?.progress ?? 0).clamp(
                                0.0,
                                1.0,
                              ),
                              minHeight: 4,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Progression: ${(((runningExportJob?.progress ?? 0).clamp(0.0, 1.0)) * 100).toStringAsFixed(1)}%',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.cyberpunk.textMuted,
                                  ),
                            ),
                            if (queuedExportsCount > 0) ...<Widget>[
                              const SizedBox(height: 6),
                              Text(
                                '$queuedExportsCount export(s) en attente...',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: context.cyberpunk.textMuted,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (exportState.errorMessage != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.6),
                          ),
                          color: Theme.of(
                            context,
                          ).colorScheme.error.withValues(alpha: 0.08),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: SelectableText(
                                exportState.errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copier l erreur',
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: () {
                                _copyToClipboard(
                                  context,
                                  exportState.errorMessage!,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Jobs export',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    ...exportState.jobs.take(6).map((ExportJob job) {
                      final String jobMessage =
                          '${job.presetLabel}: ${statusLabelBuilder(job.status)}'
                          '${job.message != null ? ' (${job.message})' : ''}';
                      final bool isSucceeded =
                          job.status == ExportJobStatus.succeeded;
                      final bool isRunning =
                          job.status == ExportJobStatus.running;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColorBuilder(context, job.status),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                jobMessage,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            IconButton(
                              tooltip: isRunning
                                  ? 'Annuler cet export'
                                  : isSucceeded
                                  ? 'Ouvrir le fichier exporte dans Finder'
                                  : 'Copier ce message',
                              icon: Icon(
                                isRunning
                                    ? Icons.close_rounded
                                    : isSucceeded
                                    ? Icons.insert_drive_file_outlined
                                    : Icons.copy_rounded,
                                size: 16,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: () {
                                if (isRunning) {
                                  onCancelRunningExport();
                                  return;
                                }
                                if (isSucceeded) {
                                  _openExportInFinder(job.outputPath);
                                  return;
                                }
                                _copyToClipboard(context, jobMessage);
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudioTopBar extends StatelessWidget {
  const _StudioTopBar({
    required this.isProjectLoading,
    required this.isMediaLoading,
    required this.comfortModeEnabled,
    required this.onCreateProject,
    required this.onImportMedia,
    required this.onSaveProject,
    required this.onLoadProject,
    required this.onToggleComfortMode,
  });

  final bool isProjectLoading;
  final bool isMediaLoading;
  final bool comfortModeEnabled;
  final VoidCallback onCreateProject;
  final VoidCallback onImportMedia;
  final VoidCallback onSaveProject;
  final VoidCallback onLoadProject;
  final ValueChanged<bool> onToggleComfortMode;

  ButtonStyle _desktopActionButtonStyle() {
    return ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size(132, 40)),
      visualDensity: VisualDensity.standard,
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle actionStyle = _desktopActionButtonStyle();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cyberpunk.border),
        color: context.cyberpunk.bgSecondary,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            Text(
              'PocketSunoMaker',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: context.cyberpunk.neonPink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 16),
            FilterChip(
              label: const Text('Confort visuel'),
              selected: comfortModeEnabled,
              onSelected: onToggleComfortMode,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: isProjectLoading ? null : onCreateProject,
              style: actionStyle,
              icon: const Icon(Icons.add),
              label: Text(isProjectLoading ? 'Creation...' : 'Nouveau'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: isMediaLoading ? null : onImportMedia,
              style: actionStyle,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Importer'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: isProjectLoading ? null : onSaveProject,
              style: actionStyle,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Sauvegarder'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: isProjectLoading ? null : onLoadProject,
              style: actionStyle,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Charger'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelShell extends StatefulWidget {
  const _PanelShell({
    required this.title,
    required this.child,
    required this.comfortModeEnabled,
    this.headerTrailing,
  });

  final String title;
  final Widget child;
  final bool comfortModeEnabled;
  final Widget? headerTrailing;

  @override
  State<_PanelShell> createState() => _PanelShellState();
}

class _PanelShellState extends State<_PanelShell> {
  static const Duration _hoverDuration = Duration(milliseconds: 140);
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: _hoverDuration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isHovered
                ? context.cyberpunk.neonBlue.withValues(
                    alpha: widget.comfortModeEnabled ? 0.22 : 0.45,
                  )
                : context.cyberpunk.border,
          ),
          boxShadow: _isHovered && !widget.comfortModeEnabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: context.cyberpunk.neonBlue.withValues(alpha: 0.12),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (widget.headerTrailing != null) widget.headerTrailing!,
                  ],
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineToolHelpRow extends StatelessWidget {
  const _TimelineToolHelpRow({
    required this.shortcut,
    required this.title,
    required this.description,
  });

  final String shortcut;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: context.cyberpunk.bgSecondary,
              border: Border.all(color: context.cyberpunk.border),
            ),
            child: Text(
              shortcut,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.cyberpunk.neonBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.cyberpunk.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.cyberpunk.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineResizeHandle extends StatelessWidget {
  const _TimelineResizeHandle({required this.onVerticalDragUpdate});

  final ValueChanged<double> onVerticalDragUpdate;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        onVerticalDragUpdate: (DragUpdateDetails details) {
          onVerticalDragUpdate(details.delta.dy);
        },
        child: Container(
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.cyberpunk.border),
            color: context.cyberpunk.bgPrimary.withValues(alpha: 0.32),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: context.cyberpunk.textMuted.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
        border: Border.all(color: Theme.of(context).colorScheme.error),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

class _StudioStatusBar extends StatelessWidget {
  const _StudioStatusBar({
    required this.isPlaying,
    required this.currentPositionMs,
    required this.projectName,
    required this.exportJobsCount,
    required this.isExporting,
    required this.activeExportLabel,
  });

  final bool isPlaying;
  final int currentPositionMs;
  final String? projectName;
  final int exportJobsCount;
  final bool isExporting;
  final String? activeExportLabel;

  @override
  Widget build(BuildContext context) {
    final String positionLabel = (currentPositionMs / 1000).toStringAsFixed(2);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cyberpunk.border),
        color: context.cyberpunk.bgSecondary,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isPlaying ? Icons.play_circle : Icons.pause_circle,
            size: 14,
            color: isPlaying
                ? context.cyberpunk.neonBlue
                : context.cyberpunk.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            isPlaying ? 'Lecture' : 'Pause',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 14),
          Text(
            'Tempo: ${positionLabel}s',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 14),
          Text(
            projectName ?? 'Sans projet',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.cyberpunk.textMuted),
          ),
          const Spacer(),
          if (isExporting)
            Text(
              activeExportLabel == null
                  ? 'Export en cours...'
                  : 'Export: $activeExportLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.cyberpunk.neonBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (isExporting) const SizedBox(width: 12),
          Text(
            'Exports: $exportJobsCount',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
