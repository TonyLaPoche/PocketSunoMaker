import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../../media_import/presentation/controllers/media_import_controller.dart';
import '../../../media_import/presentation/widgets/media_bin_panel.dart';
import '../../../preview/presentation/controllers/preview_controller.dart';
import '../../../preview/presentation/controllers/preview_audio_sync_controller.dart';
import '../../../preview/presentation/widgets/preview_panel.dart';
import '../../domain/entities/export_preset.dart';
import '../../domain/entities/project.dart';
import '../../domain/entities/track.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('PocketSunoMaker')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Base clean architecture prete.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Phase 1 active: creation de projet + import media local.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: projectState.isLoading
                      ? null
                      : projectController.createNewProject,
                  icon: const Icon(Icons.add),
                  label: Text(
                    projectState.isLoading
                        ? 'Creation en cours...'
                        : 'Nouveau projet',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: mediaState.isLoading
                      ? null
                      : mediaController.pickMediaFiles,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Importer medias'),
                ),
                OutlinedButton.icon(
                  onPressed: projectState.isLoading
                      ? null
                      : projectController.saveCurrentProject,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Sauvegarder .psm'),
                ),
                OutlinedButton.icon(
                  onPressed: projectState.isLoading
                      ? null
                      : projectController.loadProjectFromDisk,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Charger .psm'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (projectState.currentProject != null)
              Text(
                'Projet courant: ${projectState.currentProject!.name} '
                '(${projectState.currentProject!.canvasWidth}x${projectState.currentProject!.canvasHeight}, '
                '${projectState.currentProject!.fps}fps)',
              ),
            if (projectState.projectFilePath != null)
              Text(
                'Fichier projet: ${projectState.projectFilePath!}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.cyberpunk.textMuted,
                ),
              ),
            if (projectState.errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                projectState.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (mediaState.errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                mediaState.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: 320,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Media Bin',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Expanded(
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
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: context.cyberpunk.bgSecondary,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    child: MediaBinPanel(
                                      assets: mediaState.assets,
                                      isLoading: mediaState.isLoading,
                                      canAddToTimeline:
                                          projectState.currentProject != null,
                                      onAddToTimeline:
                                          projectController.addAssetToTimeline,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ListView(
                          children: <Widget>[
                            Text(
                              'Presets export cibles',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            ...ExportPreset.defaults.map(
                              (ExportPreset preset) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '- ${preset.label}: ${preset.width}x${preset.height} @ ${preset.frameRate}fps',
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            PreviewPanel(
                              project: projectState.currentProject,
                              state: previewState,
                              onTogglePlayPause:
                                  previewController.togglePlayPause,
                              onScrubStart: previewController.beginScrub,
                              onScrubEnd: previewController.endScrub,
                              onSeekTo: previewController.seekTo,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Timeline (base):',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 220,
                              child: TimelinePanel(
                                project: projectState.currentProject,
                                playheadMs: previewState.currentPositionMs,
                                onMoveClipByDelta:
                                    projectController.moveClipByDelta,
                                onTrimClipStartByDelta:
                                    projectController.trimClipStartByDelta,
                                onTrimClipEndByDelta:
                                    projectController.trimClipEndByDelta,
                                onRemoveClip: projectController.removeClip,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (projectState.currentProject == null)
                              const Text(
                                '- Cree un projet pour activer la timeline.',
                              )
                            else ...<Widget>[
                              Text(
                                '- Duree projet: ${projectState.currentProject!.durationMs} ms',
                              ),
                              ...projectState.currentProject!.tracks.map(
                                (Track track) => Text(
                                  '- ${track.type.name} track #${track.index}: ${track.clips.length} clip(s)',
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              'Metadonnees medias via ffprobe: actif.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
