import 'package:flutter/material.dart';

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../domain/entities/media_asset.dart';

class MediaBinPanel extends StatelessWidget {
  const MediaBinPanel({
    required this.assets,
    required this.isLoading,
    required this.onAddToTimeline,
    required this.onRemoveAsset,
    required this.canAddToTimeline,
    super.key,
  });

  final List<MediaAsset> assets;
  final bool isLoading;
  final ValueChanged<MediaAsset> onAddToTimeline;
  final ValueChanged<MediaAsset> onRemoveAsset;
  final bool canAddToTimeline;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (assets.isEmpty) {
      return const Center(child: Text('Aucun media importe pour le moment.'));
    }

    return ListView.separated(
      itemCount: assets.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final MediaAsset asset = assets[index];
        return ListTile(
          dense: true,
          leading: Icon(
            _iconForKind(asset.kind),
            color: context.cyberpunk.neonBlue,
          ),
          title: Text(asset.fileName),
          subtitle: Text(
            '${asset.kindLabel} - ${_formatBytes(asset.sizeBytes)}\n${asset.technicalSummary}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.cyberpunk.textMuted),
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                onPressed: canAddToTimeline
                    ? () => onAddToTimeline(asset)
                    : null,
                tooltip: canAddToTimeline
                    ? 'Ajouter a la timeline'
                    : 'Cree d abord un projet',
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                onPressed: () => onRemoveAsset(asset),
                tooltip: 'Supprimer du Media Bin',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForKind(MediaKind kind) {
    switch (kind) {
      case MediaKind.video:
        return Icons.movie_outlined;
      case MediaKind.audio:
        return Icons.audiotrack_outlined;
      case MediaKind.image:
        return Icons.image_outlined;
      case MediaKind.unknown:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
