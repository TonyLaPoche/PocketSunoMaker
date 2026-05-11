import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/export_preset.dart';
import '../controllers/project_controller.dart';

class ProjectHomePage extends ConsumerWidget {
  const ProjectHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectControllerProvider);
    final controller = ref.read(projectControllerProvider.notifier);

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
              'Prochaine etape: timeline + import media + preview.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: state.isLoading ? null : controller.createNewProject,
              icon: const Icon(Icons.add),
              label: Text(
                state.isLoading ? 'Creation en cours...' : 'Nouveau projet',
              ),
            ),
            const SizedBox(height: 16),
            if (state.currentProject != null)
              Text(
                'Projet courant: ${state.currentProject!.name} '
                '(${state.currentProject!.canvasWidth}x${state.currentProject!.canvasHeight}, '
                '${state.currentProject!.fps}fps)',
              ),
            if (state.errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Presets export cibles:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...ExportPreset.defaults.map(
              (ExportPreset preset) => Text(
                '- ${preset.label}: ${preset.width}x${preset.height} '
                '@ ${preset.frameRate}fps',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
