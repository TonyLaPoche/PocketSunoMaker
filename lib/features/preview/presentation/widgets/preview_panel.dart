import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../../project/domain/entities/clip.dart';
import '../../../project/domain/entities/project.dart';
import '../controllers/preview_state.dart';
import 'preview_viewport.dart';

class PreviewPanel extends StatefulWidget {
  const PreviewPanel({
    required this.project,
    required this.state,
    required this.audioReactiveLevel,
    required this.onTogglePlayPause,
    required this.onScrubStart,
    required this.onScrubEnd,
    required this.onSeekTo,
    this.selectedTextClipId,
    this.onTextClipSelected,
    this.onMoveSelectedTextByDelta,
    this.showGuides = false,
    this.outputWidth,
    this.outputHeight,
    this.onCaptureFrameProviderReady,
    super.key,
  });

  final Project? project;
  final PreviewState state;
  final double audioReactiveLevel;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;
  final ValueChanged<int> onSeekTo;
  final String? selectedTextClipId;
  final void Function(String trackId, Clip clip)? onTextClipSelected;
  final ValueChanged<Offset>? onMoveSelectedTextByDelta;
  final bool showGuides;
  final int? outputWidth;
  final int? outputHeight;
  final void Function(Future<Uint8List?> Function() captureFrame)?
  onCaptureFrameProviderReady;

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  double _viewportFactor = 0.55;
  final GlobalKey _previewBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCaptureFrameProviderReady?.call(_capturePreviewFramePng);
    });
  }

  @override
  void didUpdateWidget(covariant PreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCaptureFrameProviderReady?.call(_capturePreviewFramePng);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return _PanelCard(
        child: const Center(
          child: Text(
            'Preview inactive: cree un projet pour demarrer la lecture.',
          ),
        ),
      );
    }

    return _PanelCard(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double viewportHeight =
              (constraints.maxHeight * _viewportFactor)
                  .clamp(120.0, constraints.maxHeight * 0.9)
                  .toDouble();
          return Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Preview transport',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reduire preview',
                        onPressed: () {
                          setState(() {
                            _viewportFactor = (_viewportFactor - 0.05)
                                .clamp(0.35, 0.9)
                                .toDouble();
                          });
                        },
                        icon: const Icon(Icons.zoom_out),
                      ),
                      IconButton(
                        tooltip: 'Agrandir preview',
                        onPressed: () {
                          setState(() {
                            _viewportFactor = (_viewportFactor + 0.05)
                                .clamp(0.35, 0.9)
                                .toDouble();
                          });
                        },
                        icon: const Icon(Icons.zoom_in),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PreviewViewport(
                    project: widget.project!,
                    positionMs: widget.state.currentPositionMs,
                    isPlaying: widget.state.isPlaying,
                    audioReactiveLevel: widget.audioReactiveLevel,
                    viewportHeight: viewportHeight,
                    selectedTextClipId: widget.selectedTextClipId,
                    onTextClipSelected: widget.onTextClipSelected,
                    onMoveSelectedTextByDelta: widget.onMoveSelectedTextByDelta,
                    showGuides: widget.showGuides,
                    outputWidth: widget.outputWidth,
                    outputHeight: widget.outputHeight,
                    captureBoundaryKey: _previewBoundaryKey,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: widget.state.durationMs <= 0
                            ? null
                            : widget.onTogglePlayPause,
                        icon: Icon(
                          widget.state.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(widget.state.isPlaying ? 'Pause' : 'Play'),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_formatTime(widget.state.currentPositionMs)} / ${_formatTime(widget.state.durationMs)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.cyberpunk.textMuted,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: widget.state.durationMs <= 0
                              ? 1
                              : widget.state.durationMs.toDouble(),
                          value: widget.state.currentPositionMs
                              .clamp(
                                0,
                                widget.state.durationMs <= 0
                                    ? 1
                                    : widget.state.durationMs,
                              )
                              .toDouble(),
                          onChangeStart: (_) => widget.onScrubStart(),
                          onChangeEnd: (_) => widget.onScrubEnd(),
                          onChanged: (double value) =>
                              widget.onSeekTo(value.round()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTime(int ms) {
    final int totalSeconds = ms ~/ 1000;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<Uint8List?> _capturePreviewFramePng() async {
    final BuildContext? boundaryContext = _previewBoundaryKey.currentContext;
    if (boundaryContext == null) {
      return null;
    }
    final RenderObject? renderObject = boundaryContext.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      return null;
    }
    if (!renderObject.hasSize || renderObject.size.width <= 0) {
      return null;
    }
    final int? targetWidth = widget.outputWidth;
    final double pixelRatio = targetWidth == null
        ? 1.0
        : (targetWidth / renderObject.size.width).clamp(0.5, 6.0);
    final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
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
