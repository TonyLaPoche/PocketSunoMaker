import 'package:flutter/material.dart';

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../../project/domain/entities/project.dart';
import '../../../project/domain/entities/track.dart';
import '../controllers/preview_state.dart';
import '../utils/preview_clip_resolver.dart';
import 'preview_viewport.dart';

class PreviewPanel extends StatelessWidget {
  const PreviewPanel({
    required this.project,
    required this.state,
    required this.onTogglePlayPause,
    required this.onSeekTo,
    super.key,
  });

  final Project? project;
  final PreviewState state;
  final VoidCallback onTogglePlayPause;
  final ValueChanged<int> onSeekTo;

  @override
  Widget build(BuildContext context) {
    if (project == null) {
      return _PanelCard(
        child: const Center(
          child: Text(
            'Preview inactive: cree un projet pour demarrer la lecture.',
          ),
        ),
      );
    }

    final String activeVideoClip =
        findActiveClip(
          project: project!,
          positionMs: state.currentPositionMs,
          type: TrackType.video,
        )?.clip.assetPath.split('/').last ??
        'Aucun';
    final String activeAudioClip =
        findActiveClip(
          project: project!,
          positionMs: state.currentPositionMs,
          type: TrackType.audio,
        )?.clip.assetPath.split('/').last ??
        'Aucun';

    return _PanelCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Preview transport',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            PreviewViewport(
              project: project!,
              positionMs: state.currentPositionMs,
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: state.durationMs <= 0 ? null : onTogglePlayPause,
                  icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(state.isPlaying ? 'Pause' : 'Play'),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_formatTime(state.currentPositionMs)} / ${_formatTime(state.durationMs)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.cyberpunk.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Slider(
              min: 0,
              max: state.durationMs <= 0 ? 1 : state.durationMs.toDouble(),
              value: state.currentPositionMs
                  .clamp(0, state.durationMs <= 0 ? 1 : state.durationMs)
                  .toDouble(),
              onChanged: (double value) => onSeekTo(value.round()),
            ),
            Text(
              'Video active: $activeVideoClip',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.cyberpunk.neonBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Audio actif: $activeAudioClip',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.cyberpunk.neonPink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final int totalSeconds = ms ~/ 1000;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.cyberpunk.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cyberpunk.border),
      ),
      child: child,
    );
  }
}
