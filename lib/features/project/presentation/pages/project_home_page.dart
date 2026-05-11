import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../../media_import/presentation/controllers/media_import_controller.dart';
import '../../../media_import/presentation/widgets/media_bin_panel.dart';
import '../../domain/entities/export_preset.dart';
import '../../domain/entities/track.dart';
import '../controllers/project_controller.dart';

class ProjectHomePage extends ConsumerWidget {
  const ProjectHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectState = ref.watch(projectControllerProvider);
    final projectController = ref.read(projectControllerProvider.notifier);
    final mediaState = ref.watch(mediaImportControllerProvider);
    final mediaController = ref.read(mediaImportControllerProvider.notifier);

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
                style: Theme.of(context).textTheme.bodySmall,
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
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Media Bin',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ajoute tes fichiers via le bouton ou en drag & drop, puis utilise + pour envoyer un media sur la timeline.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 12),
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
                                    border: Border.all(
                                      color: mediaState.isDraggingOver
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.outlineVariant,
                                      width: mediaState.isDraggingOver ? 2 : 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
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
                    flex: 2,
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
                            Text(
                              'Timeline (base):',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
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
