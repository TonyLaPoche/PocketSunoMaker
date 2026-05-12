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
    this.showGuides = false,
    this.outputWidth,
    this.outputHeight,
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
  final bool showGuides;
  final int? outputWidth;
  final int? outputHeight;

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
    final List<ActiveClipInfo> activeTextClips = _findActiveTextClips(
      widget.project,
      widget.positionMs,
    );
    final int stageWidth = widget.outputWidth ?? widget.project.canvasWidth;
    final int stageHeight = widget.outputHeight ?? widget.project.canvasHeight;

    if (activeVisualClip == null) {
      return _ViewportFrame(
        height: widget.viewportHeight,
        child: _CanvasStage(
          canvasWidth: stageWidth,
          canvasHeight: stageHeight,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const _FallbackLabel(
                label: 'Aucun clip visuel actif',
                details: 'Place le playhead sur un clip video/image.',
              ),
              if (widget.showGuides) const _GuidesOverlay(),
              ...activeTextClips.map((ActiveClipInfo info) {
                return _TextOverlay(
                  clip: info.clip,
                  text: _resolveText(info),
                  clipPositionMs: widget.positionMs - info.clip.timelineStartMs,
                  projectCanvasWidth: widget.project.canvasWidth,
                  projectCanvasHeight: widget.project.canvasHeight,
                  stageWidth: stageWidth,
                  stageHeight: stageHeight,
                  isSelected: widget.selectedTextClipId == info.clip.id,
                  onTap: widget.onTextClipSelected == null
                      ? null
                      : () =>
                            widget.onTextClipSelected!(info.trackId, info.clip),
                  onPanUpdate: widget.onMoveSelectedTextByDelta,
                );
              }),
            ],
          ),
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
            _CanvasStage(
              canvasWidth: stageWidth,
              canvasHeight: stageHeight,
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
                  if (widget.showGuides) const _GuidesOverlay(),
                  ...activeTextClips.map((ActiveClipInfo info) {
                    return _TextOverlay(
                      clip: info.clip,
                      text: _resolveText(info),
                      clipPositionMs:
                          widget.positionMs - info.clip.timelineStartMs,
                      projectCanvasWidth: widget.project.canvasWidth,
                      projectCanvasHeight: widget.project.canvasHeight,
                      stageWidth: stageWidth,
                      stageHeight: stageHeight,
                      isSelected: widget.selectedTextClipId == info.clip.id,
                      onTap: widget.onTextClipSelected == null
                          ? null
                          : () => widget.onTextClipSelected!(
                              info.trackId,
                              info.clip,
                            ),
                      onPanUpdate: widget.onMoveSelectedTextByDelta,
                    );
                  }),
                ],
              ),
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
            _CanvasStage(
              canvasWidth: stageWidth,
              canvasHeight: stageHeight,
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
                  if (widget.showGuides) const _GuidesOverlay(),
                  ...activeTextClips.map((ActiveClipInfo info) {
                    return _TextOverlay(
                      clip: info.clip,
                      text: _resolveText(info),
                      clipPositionMs:
                          widget.positionMs - info.clip.timelineStartMs,
                      projectCanvasWidth: widget.project.canvasWidth,
                      projectCanvasHeight: widget.project.canvasHeight,
                      stageWidth: stageWidth,
                      stageHeight: stageHeight,
                      isSelected: widget.selectedTextClipId == info.clip.id,
                      onTap: widget.onTextClipSelected == null
                          ? null
                          : () => widget.onTextClipSelected!(
                              info.trackId,
                              info.clip,
                            ),
                      onPanUpdate: widget.onMoveSelectedTextByDelta,
                    );
                  }),
                ],
              ),
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

  List<ActiveClipInfo> _findActiveTextClips(Project project, int positionMs) {
    final List<({Track track, project_clip.Clip clip})> active =
        <({Track track, project_clip.Clip clip})>[];
    for (final Track track in project.tracks) {
      if (track.type != TrackType.text) {
        continue;
      }
      for (final project_clip.Clip clip in track.clips) {
        final int clipStart = clip.timelineStartMs;
        final int clipEnd = clip.timelineStartMs + clip.durationMs;
        if (positionMs < clipStart || positionMs > clipEnd) {
          continue;
        }
        active.add((track: track, clip: clip));
      }
    }
    active.sort((a, b) {
      final int byTrack = a.track.index.compareTo(b.track.index);
      if (byTrack != 0) {
        return byTrack;
      }
      return a.clip.timelineStartMs.compareTo(b.clip.timelineStartMs);
    });
    return active
        .map(
          (entry) => ActiveClipInfo(
            clip: entry.clip,
            trackId: entry.track.id,
            sourcePositionMs: positionMs - entry.clip.timelineStartMs,
          ),
        )
        .toList(growable: false);
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

class _CanvasStage extends StatelessWidget {
  const _CanvasStage({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.child,
  });

  final int canvasWidth;
  final int canvasHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }
        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  width: 1.6,
                  color: context.cyberpunk.neonBlue.withValues(alpha: 0.9),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: context.cyberpunk.neonPink.withValues(alpha: 0.30),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: context.cyberpunk.neonBlue.withValues(alpha: 0.22),
                    blurRadius: 26,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: canvasWidth.toDouble(),
                  height: canvasHeight.toDouble(),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GuidesOverlay extends StatelessWidget {
  const _GuidesOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GuidesPainter(color: context.cyberpunk.neonBlue),
      ),
    );
  }
}

class _GuidesPainter extends CustomPainter {
  const _GuidesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final Paint major = Paint()
      ..color = color.withValues(alpha: 0.26)
      ..strokeWidth = 1;
    final Paint minor = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    final List<double> vxMinor = <double>[0.25, 0.5, 0.75];
    final List<double> hyMinor = <double>[0.25, 0.5, 0.75];
    for (final double ratio in vxMinor) {
      final double x = size.width * ratio;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        ratio == 0.5 ? major : minor,
      );
    }
    for (final double ratio in hyMinor) {
      final double y = size.height * ratio;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        ratio == 0.5 ? major : minor,
      );
    }
    final Paint border = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, border);
  }

  @override
  bool shouldRepaint(covariant _GuidesPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _TextOverlay extends StatelessWidget {
  const _TextOverlay({
    required this.clip,
    required this.text,
    required this.clipPositionMs,
    required this.projectCanvasWidth,
    required this.projectCanvasHeight,
    required this.stageWidth,
    required this.stageHeight,
    required this.isSelected,
    this.onTap,
    this.onPanUpdate,
  });

  final project_clip.Clip clip;
  final String text;
  final int clipPositionMs;
  final int projectCanvasWidth;
  final int projectCanvasHeight;
  final int stageWidth;
  final int stageHeight;
  final bool isSelected;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onPanUpdate;

  @override
  Widget build(BuildContext context) {
    final double sx = stageWidth / math.max(1, projectCanvasWidth);
    final double sy = stageHeight / math.max(1, projectCanvasHeight);
    final double textScale = math.min(sx, sy);
    final double textOpacity = clip.opacity.clamp(0.0, 1.0);
    final double textRotationRad = clip.rotationDeg * (math.pi / 180.0);
    final _TextOverlayAnimation overlayAnimation = _resolveAnimation();
    final TextStyle textStyle = TextStyle(
      color: _colorFromHex(
        clip.textColorHex,
        fallback: context.cyberpunk.textPrimary,
      ),
      fontWeight: clip.textBold ? FontWeight.w700 : FontWeight.w500,
      fontStyle: clip.textItalic ? FontStyle.italic : FontStyle.normal,
      fontSize: (clip.textFontSizePx * textScale).clamp(12.0, 240.0),
      fontFamily: clip.textFontFamily,
      height: 1.1,
    );
    final Color backgroundColor = _colorFromHex(
      clip.textBackgroundHex,
      fallback: Colors.black,
    );
    final BorderSide? borderSide = isSelected
        ? BorderSide(color: context.cyberpunk.neonPink)
        : clip.textShowBorder
        ? BorderSide(color: context.cyberpunk.neonBlue.withValues(alpha: 0.35))
        : null;
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(
          clip.textPosXPx * sx,
          clip.textPosYPx * sy + overlayAnimation.offsetYPx * sy,
        ),
        child: Transform.rotate(
          angle: textRotationRad,
          child: GestureDetector(
            onTap: onTap,
            onPanUpdate: isSelected && onPanUpdate != null
                ? (DragUpdateDetails details) => onPanUpdate!(
                    Offset(details.delta.dx / sx, details.delta.dy / sy),
                  )
                : null,
            child: Opacity(
              opacity: (textOpacity * overlayAnimation.opacityFactor).clamp(
                0.0,
                1.0,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: clip.textShowBackground
                      ? backgroundColor.withValues(alpha: 0.62)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: borderSide == null
                      ? null
                      : Border.fromBorderSide(borderSide),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
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

  _TextOverlayAnimation _resolveAnimation() {
    final int clipDurationMs = math.max(1, clip.durationMs);
    final int localMs = clipPositionMs.clamp(0, clipDurationMs);
    final int entryDurationMs = clip.textEntryDurationMs.clamp(
      0,
      clipDurationMs,
    );
    final int exitDurationMs = clip.textExitDurationMs.clamp(0, clipDurationMs);
    final int remainingMs = clipDurationMs - localMs;
    double alphaFactor = 1.0;
    double offsetYPx = 0.0;

    if (clip.textEntryAnimation == project_clip.TextAnimationType.fade &&
        entryDurationMs > 0 &&
        localMs < entryDurationMs) {
      final double progress = localMs / entryDurationMs;
      alphaFactor *= progress.clamp(0.0, 1.0);
      offsetYPx += (1 - progress.clamp(0.0, 1.0)) * 20;
    }

    if (clip.textExitAnimation == project_clip.TextAnimationType.fade &&
        exitDurationMs > 0 &&
        remainingMs < exitDurationMs) {
      final double progress = remainingMs / exitDurationMs;
      alphaFactor *= progress.clamp(0.0, 1.0);
      offsetYPx -= (1 - progress.clamp(0.0, 1.0)) * 20;
    }

    return _TextOverlayAnimation(
      opacityFactor: alphaFactor.clamp(0.0, 1.0),
      offsetYPx: offsetYPx,
    );
  }
}

class _TextOverlayAnimation {
  const _TextOverlayAnimation({
    required this.opacityFactor,
    required this.offsetYPx,
  });

  final double opacityFactor;
  final double offsetYPx;
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
