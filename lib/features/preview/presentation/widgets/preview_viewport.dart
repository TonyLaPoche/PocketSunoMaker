import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../../project/domain/entities/project.dart';
import '../../../project/domain/entities/track.dart';
import '../models/active_clip_info.dart';
import '../utils/preview_clip_resolver.dart';

class PreviewViewport extends StatefulWidget {
  const PreviewViewport({
    required this.project,
    required this.positionMs,
    required this.isPlaying,
    this.viewportHeight = 190,
    super.key,
  });

  final Project project;
  final int positionMs;
  final bool isPlaying;
  final double viewportHeight;

  @override
  State<PreviewViewport> createState() => _PreviewViewportState();
}

class _PreviewViewportState extends State<PreviewViewport> {
  static const Set<String> _videoExtensions = <String>{
    'mp4',
    'm4v',
    'mov',
    'mkv',
    'avi',
    'webm',
  };
  static const Set<String> _imageExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'bmp',
    'tif',
    'tiff',
  };

  VideoPlayerController? _videoController;
  String? _boundVideoPath;
  int _lastSeekMs = -1000;
  int _syncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _syncPreview();
  }

  @override
  void didUpdateWidget(covariant PreviewViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPreview();
  }

  @override
  void dispose() {
    _disposeVideoController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ActiveClipInfo? activeVisualClip = findActiveClip(
      project: widget.project,
      positionMs: widget.positionMs,
      type: TrackType.video,
    );

    if (activeVisualClip == null) {
      return _ViewportFrame(
        height: widget.viewportHeight,
        child: _FallbackLabel(
          label: 'Aucun clip visuel actif',
          details: 'Place le playhead sur un clip video/image.',
        ),
      );
    }

    final String extension = p
        .extension(activeVisualClip.clip.assetPath)
        .replaceFirst('.', '')
        .toLowerCase();

    if (_imageExtensions.contains(extension)) {
      final File imageFile = File(activeVisualClip.clip.assetPath);
      if (!imageFile.existsSync()) {
        return _ViewportFrame(
          height: widget.viewportHeight,
          child: const _FallbackLabel(
            label: 'Image introuvable',
            details: 'Le fichier source est inaccessible.',
          ),
        );
      }
      return _ViewportFrame(
        height: widget.viewportHeight,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.file(imageFile, fit: BoxFit.contain),
            _CornerLabel(label: p.basename(activeVisualClip.clip.assetPath)),
          ],
        ),
      );
    }

    if (_videoExtensions.contains(extension)) {
      final VideoPlayerController? controller = _videoController;
      if (controller == null || !controller.value.isInitialized) {
        return _ViewportFrame(
          height: widget.viewportHeight,
          child: const _FallbackLabel(
            label: 'Chargement video...',
            details: 'Initialisation du decoder.',
          ),
        );
      }
      return _ViewportFrame(
        height: widget.viewportHeight,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
            _CornerLabel(label: p.basename(activeVisualClip.clip.assetPath)),
          ],
        ),
      );
    }

    return _ViewportFrame(
      height: widget.viewportHeight,
      child: _FallbackLabel(
        label: 'Format non supporte',
        details: p.basename(activeVisualClip.clip.assetPath),
      ),
    );
  }

  Future<void> _syncPreview() async {
    final ActiveClipInfo? activeVisualClip = findActiveClip(
      project: widget.project,
      positionMs: widget.positionMs,
      type: TrackType.video,
    );
    if (activeVisualClip == null) {
      _disposeVideoController();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final String extension = p
        .extension(activeVisualClip.clip.assetPath)
        .replaceFirst('.', '')
        .toLowerCase();
    if (!_videoExtensions.contains(extension)) {
      _disposeVideoController();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final String targetPath = activeVisualClip.clip.assetPath;
    if (_boundVideoPath != targetPath) {
      final int syncId = ++_syncGeneration;
      _disposeVideoController();
      final VideoPlayerController controller = VideoPlayerController.file(
        File(targetPath),
      );
      _videoController = controller;
      _boundVideoPath = targetPath;
      _lastSeekMs = -1000;
      await controller.initialize();
      if (!mounted || syncId != _syncGeneration) {
        return;
      }
      await controller.setVolume(0);
      await controller.pause();
    }

    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final int durationMs = controller.value.duration.inMilliseconds;
    int targetMs = activeVisualClip.sourcePositionMs;
    if (durationMs > 0 && targetMs > durationMs) {
      targetMs = durationMs;
    }
    if (targetMs < 0) {
      targetMs = 0;
    }

    if (widget.isPlaying) {
      final int currentMs = controller.value.position.inMilliseconds;
      if ((currentMs - targetMs).abs() > 250) {
        await controller.seekTo(Duration(milliseconds: targetMs));
      }
      if (!controller.value.isPlaying) {
        await controller.play();
      }
      _lastSeekMs = targetMs;
    } else {
      if (controller.value.isPlaying) {
        await controller.pause();
      }
      if ((targetMs - _lastSeekMs).abs() >= 80) {
        await controller.seekTo(Duration(milliseconds: targetMs));
        _lastSeekMs = targetMs;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _disposeVideoController() {
    _videoController?.dispose();
    _videoController = null;
    _boundVideoPath = null;
    _lastSeekMs = -1000;
  }
}

class _ViewportFrame extends StatelessWidget {
  const _ViewportFrame({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cyberpunk.border),
        color: Colors.black.withValues(alpha: 0.35),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _FallbackLabel extends StatelessWidget {
  const _FallbackLabel({required this.label, required this.details});

  final String label;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            details,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.cyberpunk.textMuted),
          ),
        ],
      ),
    );
  }
}

class _CornerLabel extends StatelessWidget {
  const _CornerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      bottom: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.cyberpunk.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
