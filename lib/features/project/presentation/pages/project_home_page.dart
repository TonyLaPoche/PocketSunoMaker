import 'dart:async';
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
                                    child: DropTarget(
                                      onDragEntered: (_) =>
                                          mediaController.setDraggingOver(true),
                                      onDragExited: (_) => mediaController
                                          .setDraggingOver(false),
                                      onDragDone: (DropDoneDetails details) {
                                        final List<String> paths = details.files
                                            .map((file) => file.path)
                                            .toList();
                                        mediaController.setDraggingOver(false);
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
                                      onAddTextAtPlayhead: project == null
                                          ? null
                                          : () =>
                                                projectController.addTextClipAt(
                                                  startMs: previewState
                                                      .currentPositionMs,
                                                ),
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
                              child: TimelinePanel(
                                project: project,
                                playheadMs: previewState.currentPositionMs,
                                isPlaying: previewState.isPlaying,
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

  Future<void> _showEditTextDialog({
    required BuildContext context,
    required ProjectController projectController,
    required String trackId,
    required Clip clip,
  }) async {
    final TextEditingController controller = TextEditingController(
      text: clip.textContent?.trim().isNotEmpty == true
          ? clip.textContent!
          : 'Nouveau texte',
    );
    final String? edited = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Editer texte'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
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
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Appliquer'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (edited == null || edited.isEmpty) {
      return;
    }
    projectController.updateClipTextContent(
      trackId: trackId,
      clipId: clip.id,
      text: edited,
    );
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
  });

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
                : clip.assetPath.split('/').last,
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
            FilledButton.icon(
              onPressed: onEditText,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editer texte'),
            ),
            const SizedBox(height: 6),
            Text(
              'Texte (rich text v1)',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.cyberpunk.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            _InspectorSlider(
              label: 'Position X ${values.textPosXPx.toStringAsFixed(0)} px',
              min: -900,
              max: 900,
              value: values.textPosXPx,
              activeColor: context.cyberpunk.neonBlue,
              onChanged: (double value) {
                onChanged(values.copyWith(textPosXPx: value));
              },
            ),
            _InspectorSlider(
              label: 'Position Y ${values.textPosYPx.toStringAsFixed(0)} px',
              min: -500,
              max: 500,
              value: values.textPosYPx,
              activeColor: context.cyberpunk.neonBlue,
              onChanged: (double value) {
                onChanged(values.copyWith(textPosYPx: value));
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
                onChanged(values.copyWith(textFontSizePx: value));
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
                        'Times New Roman',
                        'Courier New',
                      ]
                      .map(
                        (String family) => DropdownMenuItem<String>(
                          value: family,
                          child: Text(family),
                        ),
                      )
                      .toList(growable: false),
              onChanged: (String? family) {
                if (family == null) {
                  return;
                }
                onChanged(values.copyWith(textFontFamily: family));
              },
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                FilterChip(
                  label: const Text('Gras'),
                  selected: values.textBold,
                  onSelected: (bool selected) {
                    onChanged(values.copyWith(textBold: selected));
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Italique'),
                  selected: values.textItalic,
                  onSelected: (bool selected) {
                    onChanged(values.copyWith(textItalic: selected));
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
                onChanged(values.copyWith(textColorHex: hex));
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
                onChanged(values.copyWith(textBackgroundHex: hex));
              },
            ),
            Divider(color: context.cyberpunk.border.withValues(alpha: 0.7)),
          ],
          if (trackType != TrackType.audio &&
              trackType != TrackType.text) ...<Widget>[
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
          if (trackType != TrackType.audio) ...<Widget>[
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
          if (trackType != TrackType.text) ...<Widget>[
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
    required this.onAddTextAtPlayhead,
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
  final VoidCallback? onAddTextAtPlayhead;
  final String Function(ExportJobStatus status) statusLabelBuilder;
  final Color Function(BuildContext context, ExportJobStatus status)
  statusColorBuilder;
  final ValueChanged<_ClipInspectorValues> onInspectorChanged;
  final VoidCallback? onEditText;
  final ValueChanged<bool> onTogglePreviewGuides;

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
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: onAddTextAtPlayhead,
                      icon: const Icon(Icons.text_fields),
                      label: const Text('Ajouter texte au playhead'),
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
                            const LinearProgressIndicator(minHeight: 4),
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
                      Text(
                        exportState.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Jobs export',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    ...exportState.jobs
                        .take(6)
                        .map(
                          (ExportJob job) => Padding(
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
                                    color: statusColorBuilder(
                                      context,
                                      job.status,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${job.presetLabel}: ${statusLabelBuilder(job.status)}'
                                    '${job.message != null ? ' (${job.message})' : ''}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
  });

  final String title;
  final Widget child;
  final bool comfortModeEnabled;

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
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ),
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
