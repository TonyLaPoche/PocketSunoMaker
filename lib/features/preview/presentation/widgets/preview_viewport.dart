import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../../project/domain/entities/project.dart';
import '../../../project/domain/entities/track.dart';
import '../../../project/domain/entities/clip.dart' as project_clip;
import '../models/active_clip_info.dart';
import '../utils/preview_clip_resolver.dart';

class PreviewViewport extends StatefulWidget {
  const PreviewViewport({
    required this.project,
    required this.positionMs,
    required this.isPlaying,
    this.viewportHeight = 190,
    this.selectedTextClipId,
    this.onTextClipSelected,
    this.onMoveSelectedTextByDelta,
    super.key,
  });

  final Project project;
  final int positionMs;
  final bool isPlaying;
  final double viewportHeight;
  final String? selectedTextClipId;
  final void Function(String trackId, project_clip.Clip clip)?
  onTextClipSelected;
  final ValueChanged<Offset>? onMoveSelectedTextByDelta;

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
    final ActiveClipInfo? activeTextClip = findActiveClip(
      project: widget.project,
      positionMs: widget.positionMs,
      type: TrackType.text,
    );

    if (activeVisualClip == null) {
      return _ViewportFrame(
        height: widget.viewportHeight,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _FallbackLabel(
              label: 'Aucun clip visuel actif',
              details: 'Place le playhead sur un clip video/image.',
            ),
            if (activeTextClip != null)
              _TextOverlay(
                clip: activeTextClip.clip,
                text: _resolveText(activeTextClip),
                isSelected: widget.selectedTextClipId == activeTextClip.clip.id,
                onTap: widget.onTextClipSelected == null
                    ? null
                    : () => widget.onTextClipSelected!(
                        activeTextClip.trackId,
                        activeTextClip.clip,
                      ),
                onPanUpdate: widget.onMoveSelectedTextByDelta,
              ),
          ],
        ),
      );
    }

    final String extension = p
        .extension(activeVisualClip.clip.assetPath)
        .replaceFirst('.', '')
        .toLowerCase();
    final double visualOpacity = _safeOpacity(activeVisualClip.clip.opacity);
    final double visualScale = _safeScale(activeVisualClip.clip.scale);
    final double visualRotationRad = _degToRad(
      activeVisualClip.clip.rotationDeg,
    );

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
            _VisualTransform(
              opacity: visualOpacity,
              scale: visualScale,
              rotationRad: visualRotationRad,
              child: Image.file(
                imageFile,
                fit: BoxFit.contain,
                errorBuilder:
                    (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) => const _FallbackLabel(
                      label: 'Image non accessible',
                      details:
                          'Reimporte ce fichier pour renouveler la permission.',
                    ),
              ),
            ),
            _CornerLabel(label: p.basename(activeVisualClip.clip.assetPath)),
            if (activeTextClip != null)
              _TextOverlay(
                clip: activeTextClip.clip,
                text: _resolveText(activeTextClip),
                isSelected: widget.selectedTextClipId == activeTextClip.clip.id,
                onTap: widget.onTextClipSelected == null
                    ? null
                    : () => widget.onTextClipSelected!(
                        activeTextClip.trackId,
                        activeTextClip.clip,
                      ),
                onPanUpdate: widget.onMoveSelectedTextByDelta,
              ),
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
            _VisualTransform(
              opacity: visualOpacity,
              scale: visualScale,
              rotationRad: visualRotationRad,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
            _CornerLabel(label: p.basename(activeVisualClip.clip.assetPath)),
            if (activeTextClip != null)
              _TextOverlay(
                clip: activeTextClip.clip,
                text: _resolveText(activeTextClip),
                isSelected: widget.selectedTextClipId == activeTextClip.clip.id,
                onTap: widget.onTextClipSelected == null
                    ? null
                    : () => widget.onTextClipSelected!(
                        activeTextClip.trackId,
                        activeTextClip.clip,
                      ),
                onPanUpdate: widget.onMoveSelectedTextByDelta,
              ),
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

  double _safeOpacity(double value) {
    return value.clamp(0.0, 1.0);
  }

  double _safeScale(double value) {
    return value.clamp(0.5, 2.0);
  }

  double _degToRad(double deg) {
    return deg * math.pi / 180.0;
  }

  String _resolveText(ActiveClipInfo info) {
    final String? text = info.clip.textContent?.trim();
    if (text == null || text.isEmpty) {
      return 'Texte';
    }
    return text;
  }
}

class _VisualTransform extends StatelessWidget {
  const _VisualTransform({
    required this.opacity,
    required this.scale,
    required this.rotationRad,
    required this.child,
  });

  final double opacity;
  final double scale;
  final double rotationRad;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: rotationRad,
        child: Transform.scale(scale: scale, child: child),
      ),
    );
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

class _TextOverlay extends StatelessWidget {
  const _TextOverlay({
    required this.clip,
    required this.text,
    required this.isSelected,
    this.onTap,
    this.onPanUpdate,
  });

  final project_clip.Clip clip;
  final String text;
  final bool isSelected;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onPanUpdate;

  @override
  Widget build(BuildContext context) {
    final TextStyle textStyle = TextStyle(
      color: _colorFromHex(
        clip.textColorHex,
        fallback: context.cyberpunk.textPrimary,
      ),
      fontWeight: clip.textBold ? FontWeight.w700 : FontWeight.w500,
      fontStyle: clip.textItalic ? FontStyle.italic : FontStyle.normal,
      fontSize: clip.textFontSizePx.clamp(12.0, 220.0),
      fontFamily: clip.textFontFamily,
      height: 1.1,
    );
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(clip.textPosXPx, clip.textPosYPx),
        child: GestureDetector(
          onTap: onTap,
          onPanUpdate: isSelected && onPanUpdate != null
              ? (DragUpdateDetails details) => onPanUpdate!(details.delta)
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _colorFromHex(
                clip.textBackgroundHex,
                fallback: Colors.black,
              ).withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? context.cyberpunk.neonPink
                    : context.cyberpunk.neonBlue.withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                text,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorFromHex(String hex, {required Color fallback}) {
    final String normalized = hex.replaceAll('#', '').trim();
    if (normalized.length != 6) {
      return fallback;
    }
    final int? rgb = int.tryParse(normalized, radix: 16);
    if (rgb == null) {
      return fallback;
    }
    return Color(0xFF000000 | rgb);
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
