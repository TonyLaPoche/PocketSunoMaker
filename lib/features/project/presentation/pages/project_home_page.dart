import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../../export/domain/entities/export_job.dart';
import '../../../export/presentation/controllers/export_queue_controller.dart';
import '../../../media_import/presentation/controllers/media_import_controller.dart';
import '../../../media_import/presentation/widgets/media_bin_panel.dart';
import '../../../preview/presentation/controllers/preview_controller.dart';
import '../../../preview/presentation/controllers/preview_audio_sync_controller.dart';
import '../../../preview/presentation/widgets/preview_panel.dart';
import '../../domain/entities/export_preset.dart';
import '../../domain/entities/project.dart';
import '../controllers/project_controller.dart';
import '../widgets/timeline_panel.dart';

class ProjectHomePage extends ConsumerWidget {
  const ProjectHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        ref
            .read(previewAudioSyncControllerProvider)
            .synchronize(
              project: project,
              positionMs: previewTuple.$1,
              shouldPlay: previewTuple.$2,
            );
      },
    );
    ref.listen(
      projectControllerProvider.select((state) => state.currentProject),
      (_, Project? project) {
        final previewState = ref.read(previewControllerProvider);
        ref
            .read(previewAudioSyncControllerProvider)
            .synchronize(
              project: project,
              positionMs: previewState.currentPositionMs,
              shouldPlay: previewState.isPlaying,
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

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          children: <Widget>[
            _StudioTopBar(
              isProjectLoading: projectState.isLoading,
              isMediaLoading: mediaState.isLoading,
              onCreateProject: projectController.createNewProject,
              onImportMedia: mediaController.pickMediaFiles,
              onSaveProject: projectController.saveCurrentProject,
              onLoadProject: projectController.loadProjectFromDisk,
            ),
            const SizedBox(height: 8),
            if (projectState.errorMessage != null ||
                mediaState.errorMessage != null)
              _ErrorBanner(
                message: projectState.errorMessage ?? mediaState.errorMessage!,
              ),
            if (projectState.errorMessage != null ||
                mediaState.errorMessage != null)
              const SizedBox(height: 8),
            Expanded(
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          width: 300,
                          child: _PanelShell(
                            title: 'Medias',
                            child: DropTarget(
                              onDragEntered: (_) =>
                                  mediaController.setDraggingOver(true),
                              onDragExited: (_) =>
                                  mediaController.setDraggingOver(false),
                              onDragDone: (DropDoneDetails details) {
                                final List<String> paths = details.files
                                    .map((file) => file.path)
                                    .toList();
                                mediaController.setDraggingOver(false);
                                mediaController.importDroppedFiles(paths);
                              },
                              child: MediaBinPanel(
                                assets: mediaState.assets,
                                isLoading: mediaState.isLoading,
                                canAddToTimeline: project != null,
                                onAddToTimeline:
                                    projectController.addAssetToTimeline,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PanelShell(
                            title: 'Lecteur',
                            child: PreviewPanel(
                              project: project,
                              state: previewState,
                              onTogglePlayPause:
                                  previewController.togglePlayPause,
                              onScrubStart: previewController.beginScrub,
                              onScrubEnd: previewController.endScrub,
                              onSeekTo: previewController.seekTo,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 280,
                          child: _PanelShell(
                            title: 'Inspecteur / Export',
                            child: ListView(
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
                                        (ExportPreset preset) =>
                                            DropdownMenuItem(
                                              value: preset,
                                              child: Text(preset.label),
                                            ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (ExportPreset? preset) {
                                    if (preset == null) {
                                      return;
                                    }
                                    exportController.selectPreset(preset);
                                  },
                                ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: project == null
                                      ? null
                                      : () => exportController.enqueueExport(
                                          project,
                                        ),
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
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      10,
                                      10,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: context.cyberpunk.neonBlue
                                            .withValues(alpha: 0.55),
                                      ),
                                      color: context.cyberpunk.neonBlue
                                          .withValues(alpha: 0.08),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                                    : 'Export en cours: ${runningExportJob.presetLabel}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: context
                                                          .cyberpunk
                                                          .neonBlue,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        const LinearProgressIndicator(
                                          minHeight: 4,
                                        ),
                                        if (queuedExportsCount > 0) ...<Widget>[
                                          const SizedBox(height: 6),
                                          Text(
                                            '$queuedExportsCount export(s) en attente...',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: context
                                                      .cyberpunk
                                                      .textMuted,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                                if (exportState.errorMessage !=
                                    null) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    exportState.errorMessage!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
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
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Container(
                                              width: 8,
                                              height: 8,
                                              margin: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: _statusColor(
                                                  context,
                                                  job.status,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${job.presetLabel}: ${_statusLabel(job.status)}'
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
                                const SizedBox(height: 12),
                                Text(
                                  'Projet',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  project == null
                                      ? 'Aucun projet actif'
                                      : '${project.name}\n${project.canvasWidth}x${project.canvasHeight} - ${project.fps} fps',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (projectState.projectFilePath !=
                                    null) ...<Widget>[
                                  const SizedBox(height: 6),
                                  Text(
                                    projectState.projectFilePath!,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: context.cyberpunk.textMuted,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 300,
                    width: double.infinity,
                    child: _PanelShell(
                      title: 'Timeline',
                      child: TimelinePanel(
                        project: project,
                        playheadMs: previewState.currentPositionMs,
                        isPlaying: previewState.isPlaying,
                        onMoveClipByDelta: projectController.moveClipByDelta,
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
}

class _StudioTopBar extends StatelessWidget {
  const _StudioTopBar({
    required this.isProjectLoading,
    required this.isMediaLoading,
    required this.onCreateProject,
    required this.onImportMedia,
    required this.onSaveProject,
    required this.onLoadProject,
  });

  final bool isProjectLoading;
  final bool isMediaLoading;
  final VoidCallback onCreateProject;
  final VoidCallback onImportMedia;
  final VoidCallback onSaveProject;
  final VoidCallback onLoadProject;

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(width: 18),
            ...<String>[
              'Fichier',
              'Edition',
              'Affichage',
              'Lecture',
              'Export',
            ].map(
              (String label) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.cyberpunk.textMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: isProjectLoading ? null : onCreateProject,
              icon: const Icon(Icons.add),
              label: Text(isProjectLoading ? 'Creation...' : 'Nouveau'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: isMediaLoading ? null : onImportMedia,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Importer'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: isProjectLoading ? null : onSaveProject,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Sauvegarder'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: isProjectLoading ? null : onLoadProject,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Charger'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(child: child),
          ],
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
