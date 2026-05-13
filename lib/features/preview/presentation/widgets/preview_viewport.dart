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
    required this.audioReactiveLevel,
    this.viewportHeight = 190,
    this.selectedTextClipId,
    this.onTextClipSelected,
    this.onMoveSelectedTextByDelta,
    this.showGuides = false,
    this.outputWidth,
    this.outputHeight,
    this.captureBoundaryKey,
    super.key,
  });

  final Project project;
  final int positionMs;
  final bool isPlaying;
  final double audioReactiveLevel;
  final double viewportHeight;
  final String? selectedTextClipId;
  final void Function(String trackId, project_clip.Clip clip)?
  onTextClipSelected;
  final ValueChanged<Offset>? onMoveSelectedTextByDelta;
  final bool showGuides;
  final int? outputWidth;
  final int? outputHeight;
  final GlobalKey? captureBoundaryKey;

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
    final List<_ActiveVisualEffect> activeVisualEffects =
        _findActiveVisualEffects(widget.project, widget.positionMs);
    final int stageWidth = widget.outputWidth ?? widget.project.canvasWidth;
    final int stageHeight = widget.outputHeight ?? widget.project.canvasHeight;

    if (activeVisualClip == null) {
      return _ViewportFrame(
        height: widget.viewportHeight,
        child: _CanvasStage(
          canvasWidth: stageWidth,
          canvasHeight: stageHeight,
          captureBoundaryKey: widget.captureBoundaryKey,
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
              captureBoundaryKey: widget.captureBoundaryKey,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _applyVisualEffects(
                    effects: activeVisualEffects,
                    child: _VisualTransform(
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
              captureBoundaryKey: widget.captureBoundaryKey,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _applyVisualEffects(
                    effects: activeVisualEffects,
                    child: _VisualTransform(
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

  List<_ActiveVisualEffect> _findActiveVisualEffects(
    Project project,
    int positionMs,
  ) {
    final List<_ActiveVisualEffect> effects = <_ActiveVisualEffect>[];
    for (final Track track in project.tracks) {
      if (track.type != TrackType.visualEffect) {
        continue;
      }
      for (final project_clip.Clip clip in track.clips) {
        final project_clip.VisualEffectType? type = clip.visualEffectType;
        if (type == null) {
          continue;
        }
        final int clipStart = clip.timelineStartMs;
        final int clipEnd = clip.timelineStartMs + clip.durationMs;
        if (positionMs < clipStart || positionMs > clipEnd) {
          continue;
        }
        effects.add(
          _ActiveVisualEffect(
            type: type,
            timelineMs: positionMs,
            localMs: (positionMs - clipStart).clamp(0, clip.durationMs),
            intensity: clip.effectIntensity.clamp(0.1, 1.0),
            shakeAmplitudePx: clip.effectShakeAmplitudePx.clamp(2.0, 40.0),
            shakeFrequencyHz: clip.effectShakeFrequencyHz.clamp(4.0, 60.0),
            shakeAudioSync: clip.effectShakeAudioSync,
            shakeAutoBpm: clip.effectShakeAutoBpm,
            shakeDetectedBpm: clip.effectShakeDetectedBpm.clamp(60.0, 220.0),
            glitchTearStrength: clip.effectGlitchTearStrength.clamp(0.05, 1.0),
            glitchNoiseAmount: clip.effectGlitchNoiseAmount.clamp(0.0, 1.0),
            glitchColorA: _parseHexColor(
              clip.effectGlitchColorAHex,
              fallback: const Color(0xFF00E5FF),
            ),
            glitchColorB: _parseHexColor(
              clip.effectGlitchColorBHex,
              fallback: const Color(0xFFFF00E6),
            ),
            glitchAutoColors: clip.effectGlitchAutoColors,
            glitchAudioSync: clip.effectGlitchAudioSync,
            glitchLineMix: clip.effectGlitchLineMix.clamp(0.0, 1.0),
            glitchBlockMix: clip.effectGlitchBlockMix.clamp(0.0, 1.0),
            glitchBlockSizePx: clip.effectGlitchBlockSizePx.clamp(6.0, 90.0),
          ),
        );
      }
    }
    return effects;
  }

  Widget _applyVisualEffects({
    required Widget child,
    required List<_ActiveVisualEffect> effects,
  }) {
    Widget current = child;
    for (final _ActiveVisualEffect effect in effects) {
      switch (effect.type) {
        case project_clip.VisualEffectType.glitch:
          current = _EffectGlitch(
            timelineMs: effect.timelineMs,
            localMs: effect.localMs,
            intensity: effect.intensity,
            tearStrength: effect.glitchTearStrength,
            noiseAmount: effect.glitchNoiseAmount,
            colorA: effect.glitchColorA,
            colorB: effect.glitchColorB,
            autoColors: effect.glitchAutoColors,
            audioSync: effect.glitchAudioSync,
            audioReactiveLevel: widget.audioReactiveLevel,
            lineMix: effect.glitchLineMix,
            blockMix: effect.glitchBlockMix,
            blockSizePx: effect.glitchBlockSizePx,
            child: current,
          );
          break;
        case project_clip.VisualEffectType.shake:
          current = _EffectShake(
            timelineMs: effect.timelineMs,
            localMs: effect.localMs,
            intensity: effect.intensity,
            amplitudePx: effect.shakeAmplitudePx,
            frequencyHz: effect.shakeFrequencyHz,
            audioSync: effect.shakeAudioSync,
            autoBpm: effect.shakeAutoBpm,
            detectedBpm: effect.shakeDetectedBpm,
            audioReactiveLevel: widget.audioReactiveLevel,
            child: current,
          );
          break;
        case project_clip.VisualEffectType.rgbSplit:
          current = _EffectRgbSplit(
            localMs: effect.localMs,
            intensity: effect.intensity,
            child: current,
          );
          break;
        case project_clip.VisualEffectType.flash:
          current = _EffectFlash(
            localMs: effect.localMs,
            intensity: effect.intensity,
            child: current,
          );
          break;
        case project_clip.VisualEffectType.vhs:
          current = _EffectVhs(
            localMs: effect.localMs,
            intensity: effect.intensity,
            child: current,
          );
          break;
      }
    }
    return current;
  }
}

class _ActiveVisualEffect {
  const _ActiveVisualEffect({
    required this.type,
    required this.timelineMs,
    required this.localMs,
    required this.intensity,
    required this.shakeAmplitudePx,
    required this.shakeFrequencyHz,
    required this.shakeAudioSync,
    required this.shakeAutoBpm,
    required this.shakeDetectedBpm,
    required this.glitchTearStrength,
    required this.glitchNoiseAmount,
    required this.glitchColorA,
    required this.glitchColorB,
    required this.glitchAutoColors,
    required this.glitchAudioSync,
    required this.glitchLineMix,
    required this.glitchBlockMix,
    required this.glitchBlockSizePx,
  });

  final project_clip.VisualEffectType type;
  final int timelineMs;
  final int localMs;
  final double intensity;
  final double shakeAmplitudePx;
  final double shakeFrequencyHz;
  final bool shakeAudioSync;
  final bool shakeAutoBpm;
  final double shakeDetectedBpm;
  final double glitchTearStrength;
  final double glitchNoiseAmount;
  final Color glitchColorA;
  final Color glitchColorB;
  final bool glitchAutoColors;
  final bool glitchAudioSync;
  final double glitchLineMix;
  final double glitchBlockMix;
  final double glitchBlockSizePx;
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

class _EffectShake extends StatelessWidget {
  const _EffectShake({
    required this.child,
    required this.timelineMs,
    required this.localMs,
    required this.intensity,
    required this.amplitudePx,
    required this.frequencyHz,
    required this.audioSync,
    required this.autoBpm,
    required this.detectedBpm,
    required this.audioReactiveLevel,
  });

  final Widget child;
  final int timelineMs;
  final int localMs;
  final double intensity;
  final double amplitudePx;
  final double frequencyHz;
  final bool audioSync;
  final bool autoBpm;
  final double detectedBpm;
  final double audioReactiveLevel;

  @override
  Widget build(BuildContext context) {
    final double t = (audioSync ? timelineMs : localMs) / 1000.0;
    final double effectiveFrequencyHz = autoBpm && audioSync
        ? (detectedBpm / 60.0).clamp(0.8, 4.0)
        : frequencyHz;
    final double reactiveGate = audioSync
        ? math
              .pow(((audioReactiveLevel - 0.05) / 0.95).clamp(0.0, 1.0), 0.72)
              .toDouble()
        : 1.0;
    final double beatPulse = audioSync
        ? (0.62 + 0.38 * math.sin(t * math.pi * 2 * effectiveFrequencyHz).abs())
        : 1.0;
    final double amp =
        amplitudePx * (0.45 + intensity * 0.90) * beatPulse * reactiveGate;
    final double baseFreqHz = effectiveFrequencyHz * (0.6 + intensity * 0.8);
    final double dx = math.sin(t * math.pi * 2 * baseFreqHz) * amp;
    final double dy =
        math.cos(t * math.pi * 2 * (baseFreqHz * 0.77)) * amp * 0.65;
    return Transform.translate(offset: Offset(dx, dy), child: child);
  }
}

class _EffectRgbSplit extends StatelessWidget {
  const _EffectRgbSplit({
    required this.child,
    required this.localMs,
    required this.intensity,
  });

  final Widget child;
  final int localMs;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final double t = localMs / 1000.0;
    final double shift = (1.8 + math.sin(t * 18) * 1.8) * intensity;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        Transform.translate(
          offset: Offset(-shift, 0),
          child: Opacity(
            opacity: 0.20 * intensity,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.redAccent,
                BlendMode.screen,
              ),
              child: child,
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(shift, 0),
          child: Opacity(
            opacity: 0.20 * intensity,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.cyanAccent,
                BlendMode.screen,
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _EffectGlitch extends StatelessWidget {
  const _EffectGlitch({
    required this.child,
    required this.timelineMs,
    required this.localMs,
    required this.intensity,
    required this.tearStrength,
    required this.noiseAmount,
    required this.colorA,
    required this.colorB,
    required this.autoColors,
    required this.audioSync,
    required this.audioReactiveLevel,
    required this.lineMix,
    required this.blockMix,
    required this.blockSizePx,
  });

  final Widget child;
  final int timelineMs;
  final int localMs;
  final double intensity;
  final double tearStrength;
  final double noiseAmount;
  final Color colorA;
  final Color colorB;
  final bool autoColors;
  final bool audioSync;
  final double audioReactiveLevel;
  final double lineMix;
  final double blockMix;
  final double blockSizePx;

  @override
  Widget build(BuildContext context) {
    final double t = (audioSync ? timelineMs : localMs) / 1000.0;
    final double reactive = audioSync
        ? math
              .pow(((audioReactiveLevel - 0.04) / 0.96).clamp(0.0, 1.0), 0.72)
              .toDouble()
        : 1.0;
    final double amp = (2 + 16 * intensity) * (0.35 + tearStrength) * reactive;
    final double burst = math.sin(t * 22.0).abs();
    final double dx = (math.sin(t * 63.0) * amp * (0.55 + burst * 0.45)).clamp(
      -18.0,
      18.0,
    );
    final double dy = (math.cos(t * 37.0) * 1.2 * intensity).clamp(-4.0, 4.0);
    final bool highEnergy = reactive > 0.62;
    final Color autoA = highEnergy
        ? const Color(0xFF00E5FF)
        : const Color(0xFFFEE440);
    final Color autoB = highEnergy
        ? const Color(0xFFFF00E6)
        : const Color(0xFF7C4DFF);
    final Color cA = autoColors ? autoA : colorA;
    final Color cB = autoColors ? autoB : colorB;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Transform.translate(offset: Offset(dx, dy), child: child),
        _EffectRgbSplit(
          localMs: localMs,
          intensity: intensity * (0.35 + tearStrength * 0.40) * reactive,
          child: child,
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _GlitchSlicesPainter(
              phase: t,
              intensity: intensity,
              tearStrength: tearStrength,
              noiseAmount: noiseAmount,
              colorA: cA,
              colorB: cB,
              lineMix: lineMix,
              blockMix: blockMix,
              blockSizePx: blockSizePx,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _GlitchSlicesPainter extends CustomPainter {
  const _GlitchSlicesPainter({
    required this.phase,
    required this.intensity,
    required this.tearStrength,
    required this.noiseAmount,
    required this.colorA,
    required this.colorB,
    required this.lineMix,
    required this.blockMix,
    required this.blockSizePx,
  });

  final double phase;
  final double intensity;
  final double tearStrength;
  final double noiseAmount;
  final Color colorA;
  final Color colorB;
  final double lineMix;
  final double blockMix;
  final double blockSizePx;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint barA = Paint()
      ..color = colorA.withValues(
        alpha: (0.05 + (0.14 + noiseAmount * 0.10) * intensity).clamp(
          0.0,
          0.45,
        ),
      )
      ..blendMode = BlendMode.plus;
    final Paint barB = Paint()
      ..color = colorB.withValues(
        alpha: (0.04 + (0.12 + noiseAmount * 0.10) * intensity).clamp(
          0.0,
          0.42,
        ),
      )
      ..blendMode = BlendMode.plus;
    final Paint darkLine = Paint()
      ..color = Colors.black.withValues(alpha: 0.14 + 0.24 * intensity)
      ..strokeWidth = 1.0;
    final Paint darkGapLine = Paint()
      ..color = Colors.black.withValues(alpha: 0.08 + 0.14 * intensity)
      ..strokeWidth = 1.0;

    final int bands = (2 + (3 + intensity * 9 + tearStrength * 10) * lineMix)
        .round();
    for (int i = 0; i < bands; i++) {
      final double seed = phase * (7.0 + i * 0.9) + i * 1.618;
      final double y = ((math.sin(seed) + 1) * 0.5) * size.height;
      final double h =
          (1.5 +
                  (math.cos(seed * 1.7).abs() *
                      (7.0 + tearStrength * 14.0) *
                      intensity *
                      lineMix))
              .clamp(1.2, 16.0);
      final double shift =
          math.cos(seed * 2.3) * (5 + 16 * intensity + 20 * tearStrength);
      final Rect r = Rect.fromLTWH(shift, y, size.width, h);
      canvas.drawRect(r, i.isEven ? barA : barB);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), darkLine);
      if (i.isEven) {
        final double gapY = (y + h + 1).clamp(0.0, size.height);
        canvas.drawLine(Offset(0, gapY), Offset(size.width, gapY), darkGapLine);
      }
    }

    final int blockCount =
        (2 + (4 + intensity * 14 + noiseAmount * 18) * blockMix).round();
    final double baseW = blockSizePx.clamp(6.0, 90.0);
    final double baseH = (blockSizePx * 0.52).clamp(4.0, 48.0);
    for (int i = 0; i < blockCount; i++) {
      final double seed = phase * (5.3 + i * 0.47) + i * 2.17;
      final double x = ((math.sin(seed * 1.41) + 1) * 0.5) * size.width;
      final double y = ((math.cos(seed * 1.77) + 1) * 0.5) * size.height;
      final double w = (baseW * (0.55 + (math.sin(seed * 2.1).abs() * 1.35)))
          .clamp(6.0, size.width * 0.45);
      final double h = (baseH * (0.65 + (math.cos(seed * 2.7).abs() * 1.20)))
          .clamp(3.0, size.height * 0.20);
      final double shift = math.sin(seed * 3.2) * (8 + tearStrength * 20);
      final Rect rect = Rect.fromLTWH(
        (x + shift).clamp(0.0, math.max(0.0, size.width - w)),
        y.clamp(0.0, math.max(0.0, size.height - h)),
        w,
        h,
      );
      canvas.drawRect(rect, i.isEven ? barA : barB);
      if (i % 3 == 0) {
        canvas.drawRect(rect.deflate(0.7), darkGapLine);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlitchSlicesPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.intensity != intensity ||
        oldDelegate.tearStrength != tearStrength ||
        oldDelegate.noiseAmount != noiseAmount ||
        oldDelegate.colorA != colorA ||
        oldDelegate.colorB != colorB ||
        oldDelegate.lineMix != lineMix ||
        oldDelegate.blockMix != blockMix ||
        oldDelegate.blockSizePx != blockSizePx;
  }
}

Color _parseHexColor(String hex, {required Color fallback}) {
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

class _EffectFlash extends StatelessWidget {
  const _EffectFlash({
    required this.child,
    required this.localMs,
    required this.intensity,
  });

  final Widget child;
  final int localMs;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final double t = localMs / 1000.0;
    final double pulse = ((math.sin(t * 14.0) + 1) / 2);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        IgnorePointer(
          child: Container(
            color: Colors.white.withValues(alpha: pulse * 0.28 * intensity),
          ),
        ),
      ],
    );
  }
}

class _EffectVhs extends StatelessWidget {
  const _EffectVhs({
    required this.child,
    required this.localMs,
    required this.intensity,
  });

  final Widget child;
  final int localMs;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColorFiltered(
          colorFilter: ColorFilter.matrix(<double>[
            1.0,
            0.0,
            0.0,
            0.0,
            -10 * intensity,
            0.0,
            0.96,
            0.0,
            0.0,
            -8 * intensity,
            0.0,
            0.0,
            0.88,
            0.0,
            -6 * intensity,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
          ]),
          child: child,
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _ScanlinesPainter(
              intensity: intensity,
              phase: localMs / 1000.0,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _ScanlinesPainter extends CustomPainter {
  const _ScanlinesPainter({required this.intensity, required this.phase});

  final double intensity;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = Colors.black.withValues(alpha: 0.12 * intensity)
      ..strokeWidth = 1;
    final double offset = (math.sin(phase * 2.0) + 1) * 1.2;
    for (double y = offset; y < size.height; y += 3.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinesPainter oldDelegate) {
    return oldDelegate.intensity != intensity || oldDelegate.phase != phase;
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
    this.captureBoundaryKey,
  });

  final int canvasWidth;
  final int canvasHeight;
  final Widget child;
  final GlobalKey? captureBoundaryKey;

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
                child: RepaintBoundary(
                  key: captureBoundaryKey,
                  child: SizedBox(
                    width: canvasWidth.toDouble(),
                    height: canvasHeight.toDouble(),
                    child: child,
                  ),
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
    final TextStyle karaokeStyle = textStyle.copyWith(
      color: _colorFromHex(
        clip.karaokeFillColorHex,
        fallback: context.cyberpunk.neonBlue,
      ),
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
          child: Transform.scale(
            scale: overlayAnimation.scaleFactor,
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
                    child: clip.karaokeEnabled
                        ? _KaraokeTextFill(
                            text: text,
                            baseStyle: textStyle,
                            fillStyle: karaokeStyle,
                            progress: _karaokeProgress(),
                          )
                        : Text(
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
    double scaleFactor = 1.0;
    final double entryScaleFrom = clip.textEntryScale.clamp(0.2, 1.0);
    final double exitScaleTo = clip.textExitScale.clamp(0.2, 1.0);

    if (entryDurationMs > 0 && localMs < entryDurationMs) {
      final double progress = (localMs / entryDurationMs).clamp(0.0, 1.0);
      if (clip.hasEntryFade) {
        alphaFactor *= progress;
      }
      if (clip.hasEntrySlideUp) {
        offsetYPx += (1 - progress) * clip.textEntryOffsetPx;
      }
      if (clip.hasEntrySlideDown) {
        offsetYPx -= (1 - progress) * clip.textEntryOffsetPx;
      }
      if (clip.hasEntryZoom) {
        scaleFactor *= entryScaleFrom + (1 - entryScaleFrom) * progress;
      }
    }

    if (exitDurationMs > 0 && remainingMs < exitDurationMs) {
      final double progress = (remainingMs / exitDurationMs).clamp(0.0, 1.0);
      if (clip.hasExitFade) {
        alphaFactor *= progress;
      }
      if (clip.hasExitSlideUp) {
        offsetYPx -= (1 - progress) * clip.textExitOffsetPx;
      }
      if (clip.hasExitSlideDown) {
        offsetYPx += (1 - progress) * clip.textExitOffsetPx;
      }
      if (clip.hasExitZoom) {
        scaleFactor *= exitScaleTo + (1 - exitScaleTo) * progress;
      }
    }

    return _TextOverlayAnimation(
      opacityFactor: alphaFactor.clamp(0.0, 1.0),
      offsetYPx: offsetYPx,
      scaleFactor: scaleFactor.clamp(0.2, 2.0),
    );
  }

  double _karaokeProgress() {
    if (!clip.karaokeEnabled) {
      return 0.0;
    }
    final int safePos = clipPositionMs.clamp(0, clip.durationMs);
    final int localMs = safePos - clip.karaokeLeadInMs;
    if (localMs <= 0) {
      return 0.0;
    }
    final int sweepMs = clip.karaokeSweepDurationMs <= 0
        ? clip.durationMs
        : clip.karaokeSweepDurationMs;
    return (localMs / math.max(1, sweepMs)).clamp(0.0, 1.0);
  }
}

class _TextOverlayAnimation {
  const _TextOverlayAnimation({
    required this.opacityFactor,
    required this.offsetYPx,
    required this.scaleFactor,
  });

  final double opacityFactor;
  final double offsetYPx;
  final double scaleFactor;
}

class _KaraokeTextFill extends StatelessWidget {
  const _KaraokeTextFill({
    required this.text,
    required this.baseStyle,
    required this.fillStyle,
    required this.progress,
  });

  final String text;
  final TextStyle baseStyle;
  final TextStyle fillStyle;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final double safeProgress = progress.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double textWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 1000;
        final double textHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : (baseStyle.fontSize ?? 24) * 1.4;
        final double edge = safeProgress <= 0
            ? 0.0001
            : safeProgress >= 1
            ? 0.9999
            : safeProgress;
        final Color baseColor = baseStyle.color ?? Colors.white;
        final Color fillColor = fillStyle.color ?? baseColor;
        final Paint karaokePaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[fillColor, fillColor, baseColor, baseColor],
            stops: <double>[0, edge, edge, 1],
          ).createShader(Rect.fromLTWH(0, 0, textWidth, textHeight));

        return Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: baseStyle.copyWith(foreground: karaokePaint),
        );
      },
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
