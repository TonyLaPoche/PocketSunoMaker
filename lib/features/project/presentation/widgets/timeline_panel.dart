import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../domain/entities/clip.dart';
import '../../domain/entities/project.dart';
import '../../domain/entities/track.dart';

enum TimelineEditTool { select, blade, trim, hand, marker }

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    required this.project,
    required this.playheadMs,
    required this.isPlaying,
    required this.onSeekTo,
    required this.onMoveClipByDelta,
    required this.onTrimClipStartByDelta,
    required this.onTrimClipEndByDelta,
    required this.onSplitClipAtPlayhead,
    required this.onRemoveClip,
    required this.onMoveClipToTrack,
    this.reducedVisualIntensity = false,
    this.onClipSelectionChanged,
    this.onRenameTextClipRequested,
    this.onRenameTrackRequested,
    super.key,
  });

  final Project? project;
  final int playheadMs;
  final bool isPlaying;
  final ValueChanged<int> onSeekTo;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
    bool useSnapping,
  })
  onMoveClipByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
    bool useSnapping,
  })
  onTrimClipStartByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
    bool useSnapping,
  })
  onTrimClipEndByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int playheadMs,
  })
  onSplitClipAtPlayhead;
  final void Function({required String trackId, required String clipId})
  onRemoveClip;
  final void Function({
    required String sourceTrackId,
    required String targetTrackId,
    required String clipId,
  })
  onMoveClipToTrack;
  final bool reducedVisualIntensity;
  final void Function(String? trackId, Clip? clip)? onClipSelectionChanged;
  final void Function({required String trackId, required Clip clip})?
  onRenameTextClipRequested;
  final void Function({required Track track})? onRenameTrackRequested;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  String? selectedClipId;
  TimelineEditTool activeTool = TimelineEditTool.select;
  double zoomLevel = 0.10;
  bool snappingEnabled = true;
  double _lastPanZoomScale = 1.0;
  final List<int> markersMs = <int>[];
  final Set<String> mutedTrackIds = <String>{};
  final Set<String> soloTrackIds = <String>{};
  final Set<String> lockedTrackIds = <String>{};
  final ScrollController horizontalScrollController = ScrollController();
  double _playheadDragAccumulatedDx = 0;
  int? _playheadDragStartMs;

  static const double _basePixelsPerSecond = 100;
  static const double _minZoom = 0.05;
  static const double _maxZoom = 3.0;
  static const double _rowHeight = 64;
  static const double _timelineStartLeft = 148;
  static const double _timelineTopPadding = 40;
  static const double _followViewportRatio = 0.35;
  static const double _followSafetyMarginPx = 160;

  @override
  void dispose() {
    horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Center(
        child: Text(
          'Timeline inactive: cree un projet pour commencer le montage.',
        ),
      );
    }

    final double pixelsPerSecond = _basePixelsPerSecond * zoomLevel;
    final int durationMs = math.max(widget.project!.durationMs, 30000);
    final double timelineWidth = (durationMs / 1000) * pixelsPerSecond + 200;
    final double playheadLeft =
        (_timelineStartLeft + (widget.playheadMs / 1000) * pixelsPerSecond)
            .clamp(0, timelineWidth)
            .toDouble();
    const double playheadLabelWidth = 72;
    const double playheadLabelHalf = playheadLabelWidth / 2;
    const double playheadLineTop = 34;
    final double playheadLabelLeft = (playheadLeft - playheadLabelHalf)
        .clamp(0.0, math.max(0.0, timelineWidth - playheadLabelWidth))
        .toDouble();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _followPlayheadDuringPlayback(playheadLeft);
    });

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyV): () {
          _setActiveTool(TimelineEditTool.select);
        },
        const SingleActivator(LogicalKeyboardKey.keyB): () {
          _setActiveTool(TimelineEditTool.blade);
        },
        const SingleActivator(LogicalKeyboardKey.keyT): () {
          _setActiveTool(TimelineEditTool.trim);
        },
        const SingleActivator(LogicalKeyboardKey.keyH): () {
          _setActiveTool(TimelineEditTool.hand);
        },
        const SingleActivator(LogicalKeyboardKey.keyM): () {
          _setActiveTool(TimelineEditTool.marker);
        },
        const SingleActivator(LogicalKeyboardKey.keyN): _toggleSnapping,
        const SingleActivator(LogicalKeyboardKey.keyS): _splitAtPlayhead,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.cyberpunk.border),
            color: context.cyberpunk.bgSecondary,
          ),
          child: Column(
            children: <Widget>[
              _TimelineToolbar(
                activeTool: activeTool,
                zoomLevel: zoomLevel,
                minZoom: _minZoom,
                maxZoom: _maxZoom,
                zoomDivisions: ((_maxZoom - _minZoom) * 100).round(),
                snappingEnabled: snappingEnabled,
                markerCount: markersMs.length,
                onToolSelected: _setActiveTool,
                onAddMarker: () {
                  setState(() {
                    if (!markersMs.contains(widget.playheadMs)) {
                      markersMs
                        ..add(widget.playheadMs)
                        ..sort();
                    }
                  });
                },
                onClearMarkers: () {
                  setState(() {
                    markersMs.clear();
                  });
                },
                onZoomChanged: (double value) {
                  setState(() {
                    zoomLevel = value;
                  });
                },
                onZoomIn: () {
                  setState(() {
                    zoomLevel = (zoomLevel + 0.02).clamp(_minZoom, _maxZoom);
                  });
                },
                onZoomOut: () {
                  setState(() {
                    zoomLevel = (zoomLevel - 0.02).clamp(_minZoom, _maxZoom);
                  });
                },
                onToggleSnapping: _toggleSnapping,
              ),
              Expanded(
                child: Listener(
                  onPointerPanZoomStart: (_) {
                    _lastPanZoomScale = 1.0;
                  },
                  onPointerPanZoomUpdate: (PointerPanZoomUpdateEvent event) {
                    final double scaleRatio = event.scale / _lastPanZoomScale;
                    _lastPanZoomScale = event.scale;
                    if ((scaleRatio - 1).abs() > 0.0005) {
                      setState(() {
                        final double target = (zoomLevel * scaleRatio).clamp(
                          _minZoom,
                          _maxZoom,
                        );
                        zoomLevel = _smoothZoom(zoomLevel, target);
                      });
                    }
                    if (!horizontalScrollController.hasClients) {
                      return;
                    }
                    final double target =
                        horizontalScrollController.offset - event.panDelta.dx;
                    final double clamped = target.clamp(
                      0.0,
                      horizontalScrollController.position.maxScrollExtent,
                    );
                    horizontalScrollController.jumpTo(clamped);
                  },
                  onPointerPanZoomEnd: (_) {
                    _lastPanZoomScale = 1.0;
                  },
                  onPointerSignal: (PointerSignalEvent event) {
                    if (event is! PointerScrollEvent) {
                      return;
                    }
                    final double dx = event.scrollDelta.dx;
                    final double dy = event.scrollDelta.dy;
                    if (dx.abs() < 0.01 && dy.abs() < 0.01) {
                      return;
                    }
                    if (!horizontalScrollController.hasClients) {
                      return;
                    }
                    final double horizontalDelta = dx.abs() > 0.01 ? dx : dy;
                    final double target =
                        horizontalScrollController.offset - horizontalDelta;
                    final double clamped = target.clamp(
                      0.0,
                      horizontalScrollController.position.maxScrollExtent,
                    );
                    horizontalScrollController.jumpTo(clamped);
                  },
                  child: SingleChildScrollView(
                    controller: horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: timelineWidth,
                      child: GestureDetector(
                        onHorizontalDragUpdate:
                            activeTool == TimelineEditTool.hand
                            ? (DragUpdateDetails details) {
                                final double target =
                                    horizontalScrollController.offset -
                                    details.delta.dx;
                                final double clamped = target.clamp(
                                  0.0,
                                  horizontalScrollController
                                      .position
                                      .maxScrollExtent,
                                );
                                horizontalScrollController.jumpTo(clamped);
                              }
                            : null,
                        child: Stack(
                          children: <Widget>[
                            Column(
                              children: <Widget>[
                                const SizedBox(height: _timelineTopPadding),
                                const Divider(height: 1),
                                if (widget.project!.tracks.isEmpty)
                                  const Expanded(
                                    child: Center(
                                      child: Text(
                                        'Ajoute des medias au projet pour creer des clips.',
                                      ),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: widget.project!.tracks.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1),
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                            final Track track =
                                                widget.project!.tracks[index];
                                            final bool hasSoloTracks =
                                                soloTrackIds.isNotEmpty;
                                            final bool isTrackMuted =
                                                mutedTrackIds.contains(
                                                  track.id,
                                                );
                                            final bool isTrackSolo =
                                                soloTrackIds.contains(track.id);
                                            final bool isTrackLocked =
                                                lockedTrackIds.contains(
                                                  track.id,
                                                );
                                            final bool isTrackDimmed =
                                                isTrackMuted ||
                                                (hasSoloTracks && !isTrackSolo);
                                            return _TimelineTrackRow(
                                              track: track,
                                              trackRowIndex: index,
                                              allTracks: widget.project!.tracks,
                                              rowHeight: _rowHeight,
                                              pixelsPerSecond: pixelsPerSecond,
                                              playheadMs: widget.playheadMs,
                                              activeTool: activeTool,
                                              selectedClipId: selectedClipId,
                                              snappingEnabled: snappingEnabled,
                                              isTrackMuted: isTrackMuted,
                                              isTrackSolo: isTrackSolo,
                                              isTrackLocked: isTrackLocked,
                                              dimmed: isTrackDimmed,
                                              reducedVisualIntensity:
                                                  widget.reducedVisualIntensity,
                                              onToggleMute: () {
                                                setState(() {
                                                  if (!mutedTrackIds.add(
                                                    track.id,
                                                  )) {
                                                    mutedTrackIds.remove(
                                                      track.id,
                                                    );
                                                  }
                                                });
                                              },
                                              onToggleSolo: () {
                                                setState(() {
                                                  if (!soloTrackIds.add(
                                                    track.id,
                                                  )) {
                                                    soloTrackIds.remove(
                                                      track.id,
                                                    );
                                                  }
                                                });
                                              },
                                              onToggleLock: () {
                                                setState(() {
                                                  if (!lockedTrackIds.add(
                                                    track.id,
                                                  )) {
                                                    lockedTrackIds.remove(
                                                      track.id,
                                                    );
                                                  }
                                                });
                                              },
                                              onSelectClip:
                                                  ({
                                                    required String trackId,
                                                    required Clip clip,
                                                  }) {
                                                    setState(() {
                                                      selectedClipId = clip.id;
                                                    });
                                                    widget
                                                        .onClipSelectionChanged
                                                        ?.call(trackId, clip);
                                                  },
                                              onMoveClipByDelta:
                                                  widget.onMoveClipByDelta,
                                              onTrimClipStartByDelta:
                                                  widget.onTrimClipStartByDelta,
                                              onTrimClipEndByDelta:
                                                  widget.onTrimClipEndByDelta,
                                              onSplitClipAtPlayhead:
                                                  widget.onSplitClipAtPlayhead,
                                              onMoveClipToTrack:
                                                  ({
                                                    required String
                                                    sourceTrackId,
                                                    required String
                                                    targetTrackId,
                                                    required String clipId,
                                                  }) {
                                                    if (lockedTrackIds.contains(
                                                      targetTrackId,
                                                    )) {
                                                      return;
                                                    }
                                                    widget.onMoveClipToTrack(
                                                      sourceTrackId:
                                                          sourceTrackId,
                                                      targetTrackId:
                                                          targetTrackId,
                                                      clipId: clipId,
                                                    );
                                                  },
                                              onRenameTextClipRequested: widget
                                                  .onRenameTextClipRequested,
                                              onRenameTrackRequested:
                                                  widget.onRenameTrackRequested,
                                              onRemoveClip:
                                                  ({
                                                    required String trackId,
                                                    required String clipId,
                                                  }) {
                                                    widget.onRemoveClip(
                                                      trackId: trackId,
                                                      clipId: clipId,
                                                    );
                                                    if (selectedClipId ==
                                                        clipId) {
                                                      setState(() {
                                                        selectedClipId = null;
                                                      });
                                                      widget
                                                          .onClipSelectionChanged
                                                          ?.call(null, null);
                                                    }
                                                  },
                                            );
                                          },
                                    ),
                                  ),
                              ],
                            ),
                            ...markersMs.map((int markerMs) {
                              final double markerLeft =
                                  (_timelineStartLeft +
                                          (markerMs / 1000) * pixelsPerSecond)
                                      .clamp(0, timelineWidth)
                                      .toDouble();
                              return Positioned(
                                left: markerLeft,
                                top: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 1.5,
                                    color: Colors.amber.withValues(alpha: 0.75),
                                  ),
                                ),
                              );
                            }),
                            Positioned(
                              left: playheadLabelLeft,
                              top: 4,
                              child: IgnorePointer(
                                child: Container(
                                  width: playheadLabelWidth,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    color: context.cyberpunk.neonBlue
                                        .withValues(alpha: 0.28),
                                    border: Border.all(
                                      color: context.cyberpunk.neonBlue
                                          .withValues(alpha: 0.9),
                                    ),
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: context.cyberpunk.neonBlue
                                            .withValues(alpha: 0.18),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    _formatTimelineTime(widget.playheadMs),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: context.cyberpunk.neonBlue,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                          letterSpacing: 0.2,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: playheadLeft - 11,
                              top: playheadLineTop - 8,
                              child: MouseRegion(
                                cursor: widget.isPlaying
                                    ? SystemMouseCursors.basic
                                    : SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: widget.isPlaying
                                      ? null
                                      : (_) {
                                          _playheadDragStartMs =
                                              widget.playheadMs;
                                          _playheadDragAccumulatedDx = 0;
                                        },
                                  onPanUpdate: widget.isPlaying
                                      ? null
                                      : (DragUpdateDetails details) {
                                          _seekPlayheadFromDrag(
                                            deltaDx: details.delta.dx,
                                            pixelsPerSecond: pixelsPerSecond,
                                            durationMs: durationMs,
                                          );
                                        },
                                  onPanEnd: widget.isPlaying
                                      ? null
                                      : (_) {
                                          _playheadDragStartMs = null;
                                          _playheadDragAccumulatedDx = 0;
                                        },
                                  onPanCancel: widget.isPlaying
                                      ? null
                                      : () {
                                          _playheadDragStartMs = null;
                                          _playheadDragAccumulatedDx = 0;
                                        },
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: context.cyberpunk.neonBlue,
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color: context.cyberpunk.neonBlue
                                                .withValues(alpha: 0.45),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: playheadLeft - 1,
                              top: playheadLineTop,
                              bottom: 0,
                              child: IgnorePointer(
                                child: Container(
                                  width: 2,
                                  color: context.cyberpunk.neonBlue.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setActiveTool(TimelineEditTool tool) {
    setState(() {
      activeTool = tool;
    });
  }

  void _toggleSnapping() {
    setState(() {
      snappingEnabled = !snappingEnabled;
    });
  }

  void _seekPlayheadFromDrag({
    required double deltaDx,
    required double pixelsPerSecond,
    required int durationMs,
  }) {
    final int startMs = _playheadDragStartMs ?? widget.playheadMs;
    _playheadDragAccumulatedDx += deltaDx;
    final int deltaMs = ((_playheadDragAccumulatedDx / pixelsPerSecond) * 1000)
        .round();
    final int targetMs = (startMs + deltaMs).clamp(0, durationMs);
    widget.onSeekTo(targetMs);
  }

  void _splitAtPlayhead() {
    final Project? project = widget.project;
    if (project == null) {
      return;
    }
    final ({String trackId, Clip clip})? selectedRef = _resolveSelectedClipRef(
      project,
    );
    if (selectedRef != null) {
      widget.onSplitClipAtPlayhead(
        trackId: selectedRef.trackId,
        clipId: selectedRef.clip.id,
        playheadMs: widget.playheadMs,
      );
      return;
    }
    final ({String trackId, Clip clip})? activeRef = _findClipAtPlayhead(
      project,
    );
    if (activeRef == null) {
      return;
    }
    widget.onSplitClipAtPlayhead(
      trackId: activeRef.trackId,
      clipId: activeRef.clip.id,
      playheadMs: widget.playheadMs,
    );
  }

  ({String trackId, Clip clip})? _resolveSelectedClipRef(Project project) {
    final String? clipId = selectedClipId;
    if (clipId == null) {
      return null;
    }
    for (final Track track in project.tracks) {
      for (final Clip clip in track.clips) {
        if (clip.id == clipId) {
          return (trackId: track.id, clip: clip);
        }
      }
    }
    return null;
  }

  ({String trackId, Clip clip})? _findClipAtPlayhead(Project project) {
    ({String trackId, Clip clip})? best;
    int bestTrackIndex = -1;
    int bestStart = -1;
    for (final Track track in project.tracks) {
      for (final Clip clip in track.clips) {
        final int start = clip.timelineStartMs;
        final int end = clip.timelineStartMs + clip.durationMs;
        if (widget.playheadMs < start || widget.playheadMs > end) {
          continue;
        }
        final bool higherTrack = track.index > bestTrackIndex;
        final bool sameTrackLaterStart =
            track.index == bestTrackIndex && start > bestStart;
        if (best == null || higherTrack || sameTrackLaterStart) {
          best = (trackId: track.id, clip: clip);
          bestTrackIndex = track.index;
          bestStart = start;
        }
      }
    }
    return best;
  }

  void _followPlayheadDuringPlayback(double playheadLeft) {
    if (!widget.isPlaying || !horizontalScrollController.hasClients) {
      return;
    }
    final ScrollPosition position = horizontalScrollController.position;
    final double currentOffset = horizontalScrollController.offset;
    final double viewportWidth = position.viewportDimension;
    final double visibleStart = currentOffset + _followSafetyMarginPx;
    final double visibleEnd =
        currentOffset + viewportWidth - _followSafetyMarginPx;
    if (playheadLeft >= visibleStart && playheadLeft <= visibleEnd) {
      return;
    }
    final double target = (playheadLeft - viewportWidth * _followViewportRatio)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if ((target - currentOffset).abs() < 1) {
      return;
    }
    horizontalScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  double _smoothZoom(double current, double target) {
    const double alpha = 0.3;
    final double next = current + (target - current) * alpha;
    if ((next - target).abs() < 0.0005) {
      return target;
    }
    return next;
  }

  String _formatTimelineTime(int ms) {
    final int totalSeconds = ms ~/ 1000;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    final int centiseconds = (ms % 1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}';
  }
}

class _TimelineToolbar extends StatelessWidget {
  const _TimelineToolbar({
    required this.activeTool,
    required this.zoomLevel,
    required this.minZoom,
    required this.maxZoom,
    required this.zoomDivisions,
    required this.snappingEnabled,
    required this.markerCount,
    required this.onToolSelected,
    required this.onAddMarker,
    required this.onClearMarkers,
    required this.onZoomChanged,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onToggleSnapping,
  });

  final TimelineEditTool activeTool;
  final double zoomLevel;
  final double minZoom;
  final double maxZoom;
  final int zoomDivisions;
  final bool snappingEnabled;
  final int markerCount;
  final ValueChanged<TimelineEditTool> onToolSelected;
  final VoidCallback onAddMarker;
  final VoidCallback onClearMarkers;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onToggleSnapping;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _ToolButton(
            label: 'Selection',
            icon: Icons.ads_click_outlined,
            isActive: activeTool == TimelineEditTool.select,
            onTap: () => onToolSelected(TimelineEditTool.select),
          ),
          _ToolButton(
            label: 'Lame',
            icon: Icons.content_cut,
            isActive: activeTool == TimelineEditTool.blade,
            onTap: () => onToolSelected(TimelineEditTool.blade),
          ),
          _ToolButton(
            label: 'Trim',
            icon: Icons.tune,
            isActive: activeTool == TimelineEditTool.trim,
            onTap: () => onToolSelected(TimelineEditTool.trim),
          ),
          _ToolButton(
            label: 'Main',
            icon: Icons.pan_tool_alt_outlined,
            isActive: activeTool == TimelineEditTool.hand,
            onTap: () => onToolSelected(TimelineEditTool.hand),
          ),
          _ToolButton(
            label: 'Marqueur',
            icon: Icons.bookmark_add_outlined,
            isActive: activeTool == TimelineEditTool.marker,
            onTap: () => onToolSelected(TimelineEditTool.marker),
          ),
          _ToolButton(
            label: snappingEnabled ? 'Snap ON' : 'Snap OFF',
            icon: Icons.grid_on_outlined,
            isActive: snappingEnabled,
            onTap: onToggleSnapping,
          ),
          TextButton.icon(
            onPressed: onAddMarker,
            icon: const Icon(Icons.add),
            label: const Text('Repere'),
          ),
          if (markerCount > 0)
            TextButton.icon(
              onPressed: onClearMarkers,
              icon: const Icon(Icons.clear_all),
              label: Text('Effacer ($markerCount)'),
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.zoom_out),
            tooltip: 'Dezoomer timeline',
          ),
          SizedBox(
            width: 140,
            child: Slider(
              min: minZoom,
              max: maxZoom,
              divisions: zoomDivisions,
              value: zoomLevel,
              onChanged: onZoomChanged,
            ),
          ),
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Zoomer timeline',
          ),
          Text(
            '${(zoomLevel * 100).round()}%',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.cyberpunk.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color border = isActive
        ? context.cyberpunk.neonPink
        : context.cyberpunk.border;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
          color: isActive
              ? context.cyberpunk.neonPink.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _TimelineTrackRow extends StatelessWidget {
  const _TimelineTrackRow({
    required this.track,
    required this.trackRowIndex,
    required this.allTracks,
    required this.rowHeight,
    required this.pixelsPerSecond,
    required this.playheadMs,
    required this.activeTool,
    required this.selectedClipId,
    required this.snappingEnabled,
    required this.isTrackMuted,
    required this.isTrackSolo,
    required this.isTrackLocked,
    required this.dimmed,
    required this.reducedVisualIntensity,
    required this.onToggleMute,
    required this.onToggleSolo,
    required this.onToggleLock,
    required this.onSelectClip,
    required this.onMoveClipByDelta,
    required this.onTrimClipStartByDelta,
    required this.onTrimClipEndByDelta,
    required this.onSplitClipAtPlayhead,
    required this.onMoveClipToTrack,
    this.onRenameTextClipRequested,
    this.onRenameTrackRequested,
    required this.onRemoveClip,
  });

  final Track track;
  final int trackRowIndex;
  final List<Track> allTracks;
  final double rowHeight;
  final double pixelsPerSecond;
  final int playheadMs;
  final TimelineEditTool activeTool;
  final String? selectedClipId;
  final bool snappingEnabled;
  final bool isTrackMuted;
  final bool isTrackSolo;
  final bool isTrackLocked;
  final bool dimmed;
  final bool reducedVisualIntensity;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSolo;
  final VoidCallback onToggleLock;
  final void Function({required String trackId, required Clip clip})
  onSelectClip;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
    bool useSnapping,
  })
  onMoveClipByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
    bool useSnapping,
  })
  onTrimClipStartByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
    bool useSnapping,
  })
  onTrimClipEndByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int playheadMs,
  })
  onSplitClipAtPlayhead;
  final void Function({
    required String sourceTrackId,
    required String targetTrackId,
    required String clipId,
  })
  onMoveClipToTrack;
  final void Function({required String trackId, required Clip clip})?
  onRenameTextClipRequested;
  final void Function({required Track track})? onRenameTrackRequested;
  final void Function({required String trackId, required String clipId})
  onRemoveClip;
  static const double _trackHeaderWidth = 148;

  @override
  Widget build(BuildContext context) {
    final bool isSelectedTrack =
        selectedClipId != null &&
        track.clips.any((Clip clip) => clip.id == selectedClipId);
    final String trackLabel = track.name?.trim().isNotEmpty == true
        ? track.name!
        : '${track.type.name.toUpperCase()} ${track.index + 1}';
    return SizedBox(
      height: rowHeight,
      child: Stack(
        children: <Widget>[
          if (isSelectedTrack)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: context.cyberpunk.neonBlue.withValues(alpha: 0.06),
                ),
              ),
            ),
          Positioned.fill(
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: _trackHeaderWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                trackLabel,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: context.cyberpunk.neonBlue,
                                      fontWeight: FontWeight.w700,
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (track.type == TrackType.text) ...<Widget>[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: 'Renommer piste',
                                child: InkWell(
                                  onTap: () {
                                    onRenameTrackRequested?.call(track: track);
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.edit_outlined,
                                      size: 12,
                                      color: context.cyberpunk.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            _TrackIconToggle(
                              tooltip: 'Mute piste',
                              icon: Icons.volume_off_outlined,
                              active: isTrackMuted,
                              onTap: onToggleMute,
                            ),
                            const SizedBox(width: 4),
                            _TrackIconToggle(
                              tooltip: 'Solo piste',
                              icon: Icons.hearing_outlined,
                              active: isTrackSolo,
                              onTap: onToggleSolo,
                            ),
                            const SizedBox(width: 4),
                            _TrackIconToggle(
                              tooltip: 'Verrouiller piste',
                              icon: Icons.lock_outline,
                              active: isTrackLocked,
                              onTap: onToggleLock,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: context.cyberpunk.border),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...track.clips.map((Clip clip) {
            final bool isTextClip = track.type == TrackType.text;
            final double clipHeight = isTextClip ? 30 : 42;
            final double left =
                _trackHeaderWidth +
                (clip.timelineStartMs / 1000) * pixelsPerSecond;
            final double width = math.max(
              (clip.durationMs / 1000) * pixelsPerSecond,
              isTextClip ? 60 : 42,
            );
            return Positioned(
              left: left,
              top: (rowHeight - clipHeight) / 2,
              child: _TimelineClipWidget(
                clip: clip,
                width: width,
                height: clipHeight,
                playheadMs: playheadMs,
                trackId: track.id,
                isTextClip: isTextClip,
                isSelected: selectedClipId == clip.id,
                canTrim:
                    (activeTool == TimelineEditTool.trim ||
                        selectedClipId == clip.id) &&
                    !isTrackLocked,
                canMove:
                    activeTool == TimelineEditTool.select && !isTrackLocked,
                canDelete:
                    activeTool == TimelineEditTool.select && !isTrackLocked,
                canBladeSplit:
                    activeTool == TimelineEditTool.blade && !isTrackLocked,
                dimmed: dimmed,
                reducedVisualIntensity: reducedVisualIntensity,
                onSelect: () => onSelectClip(trackId: track.id, clip: clip),
                onRemove: () =>
                    onRemoveClip(trackId: track.id, clipId: clip.id),
                onSplitClipAtPlayhead: onSplitClipAtPlayhead,
                onRenameTextClipRequested: isTextClip
                    ? () => onRenameTextClipRequested?.call(
                        trackId: track.id,
                        clip: clip,
                      )
                    : null,
                trackRowHeight: rowHeight,
                onMoveToTrackByRowDelta: (int rowDelta) {
                  if (!isTextClip || rowDelta == 0) {
                    return;
                  }
                  final int targetIndex = (trackRowIndex + rowDelta).clamp(
                    0,
                    allTracks.length - 1,
                  );
                  final Track targetTrack = allTracks[targetIndex];
                  if (targetTrack.id == track.id ||
                      targetTrack.type != track.type) {
                    return;
                  }
                  onMoveClipToTrack(
                    sourceTrackId: track.id,
                    targetTrackId: targetTrack.id,
                    clipId: clip.id,
                  );
                },
                displayLabel: track.type == TrackType.text
                    ? (clip.textContent?.trim().isNotEmpty == true
                          ? clip.textContent!.trim()
                          : 'Texte')
                    : p.basename(clip.assetPath),
                onTrimStartByDeltaPx: (double deltaPx) {
                  final int deltaMs = (deltaPx / pixelsPerSecond * 1000)
                      .round();
                  if (deltaMs == 0) {
                    return;
                  }
                  onTrimClipStartByDelta(
                    trackId: track.id,
                    clipId: clip.id,
                    deltaMs: deltaMs,
                    useSnapping: snappingEnabled,
                  );
                },
                onTrimEndByDeltaPx: (double deltaPx) {
                  final int deltaMs = (deltaPx / pixelsPerSecond * 1000)
                      .round();
                  if (deltaMs == 0) {
                    return;
                  }
                  onTrimClipEndByDelta(
                    trackId: track.id,
                    clipId: clip.id,
                    deltaMs: deltaMs,
                    useSnapping: snappingEnabled,
                  );
                },
                onMoveByDeltaPx: (double deltaPx) {
                  final int deltaMs = (deltaPx / pixelsPerSecond * 1000)
                      .round();
                  if (deltaMs == 0) {
                    return;
                  }
                  onMoveClipByDelta(
                    trackId: track.id,
                    clipId: clip.id,
                    deltaMs: deltaMs,
                    useSnapping: snappingEnabled,
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TrackIconToggle extends StatelessWidget {
  const _TrackIconToggle({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 24,
          height: 20,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active
                  ? context.cyberpunk.neonBlue
                  : context.cyberpunk.border,
            ),
            color: active
                ? context.cyberpunk.neonBlue.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 12,
            color: active
                ? context.cyberpunk.neonBlue
                : context.cyberpunk.textMuted,
          ),
        ),
      ),
    );
  }
}

class _TimelineClipWidget extends StatefulWidget {
  const _TimelineClipWidget({
    required this.clip,
    required this.width,
    required this.height,
    required this.playheadMs,
    required this.trackId,
    required this.isTextClip,
    required this.isSelected,
    required this.canTrim,
    required this.canMove,
    required this.canDelete,
    required this.canBladeSplit,
    required this.dimmed,
    required this.reducedVisualIntensity,
    required this.onSelect,
    required this.onRemove,
    required this.onSplitClipAtPlayhead,
    this.onRenameTextClipRequested,
    required this.trackRowHeight,
    this.onMoveToTrackByRowDelta,
    required this.displayLabel,
    required this.onTrimStartByDeltaPx,
    required this.onTrimEndByDeltaPx,
    required this.onMoveByDeltaPx,
  });

  final Clip clip;
  final double width;
  final double height;
  final int playheadMs;
  final String trackId;
  final bool isTextClip;
  final bool isSelected;
  final bool canTrim;
  final bool canMove;
  final bool canDelete;
  final bool canBladeSplit;
  final bool dimmed;
  final bool reducedVisualIntensity;
  final VoidCallback onSelect;
  final VoidCallback onRemove;
  final String displayLabel;
  final void Function({
    required String trackId,
    required String clipId,
    required int playheadMs,
  })
  onSplitClipAtPlayhead;
  final VoidCallback? onRenameTextClipRequested;
  final double trackRowHeight;
  final ValueChanged<int>? onMoveToTrackByRowDelta;
  final ValueChanged<double> onTrimStartByDeltaPx;
  final ValueChanged<double> onTrimEndByDeltaPx;
  final ValueChanged<double> onMoveByDeltaPx;

  @override
  State<_TimelineClipWidget> createState() => _TimelineClipWidgetState();
}

class _TimelineClipWidgetState extends State<_TimelineClipWidget> {
  double _dragAccumulatedDy = 0;
  bool _isDragging = false;

  void _resetDrag() {
    _dragAccumulatedDy = 0;
    _isDragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final double baseAlpha = widget.reducedVisualIntensity ? 0.68 : 0.85;
    final double glowAlpha = widget.reducedVisualIntensity ? 0.12 : 0.24;
    final double selectedGlowAlpha = widget.reducedVisualIntensity ? 0.2 : 0.35;
    final List<Color> gradientColors = widget.isTextClip
        ? <Color>[
            context.cyberpunk.neonBlue.withValues(
              alpha: widget.reducedVisualIntensity ? 0.55 : 0.72,
            ),
            context.cyberpunk.neonViolet.withValues(
              alpha: widget.reducedVisualIntensity ? 0.55 : 0.72,
            ),
          ]
        : <Color>[
            context.cyberpunk.neonPink.withValues(alpha: baseAlpha),
            context.cyberpunk.neonViolet.withValues(alpha: baseAlpha),
          ];
    final bool showDeleteIcon =
        widget.isSelected && widget.canDelete && widget.width >= 44;
    final bool showRenameIcon =
        widget.isTextClip &&
        widget.isSelected &&
        widget.onRenameTextClipRequested != null &&
        widget.width >= 64;
    final double handleWidth = widget.width < 34 ? 4 : 6;
    return Opacity(
      opacity: widget.dimmed ? 0.35 : 1,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(colors: gradientColors),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color:
                  (widget.isTextClip
                          ? context.cyberpunk.neonBlue
                          : context.cyberpunk.neonPink)
                      .withValues(alpha: glowAlpha),
              blurRadius: 12,
            ),
            if (widget.isSelected)
              BoxShadow(
                color: context.cyberpunk.neonBlue.withValues(
                  alpha: selectedGlowAlpha,
                ),
                blurRadius: 16,
                spreadRadius: 1.5,
              ),
          ],
        ),
        child: Row(
          children: <Widget>[
            _TrimHandle(
              onDrag: widget.onTrimStartByDeltaPx,
              isLeft: true,
              enabled: widget.canTrim,
              width: handleWidth,
            ),
            Expanded(
              child: MouseRegion(
                cursor: widget.isTextClip && widget.canMove
                    ? (_isDragging
                          ? SystemMouseCursors.grabbing
                          : SystemMouseCursors.grab)
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  onPanStart: widget.canMove
                      ? (_) {
                          setState(() {
                            _isDragging = true;
                            _dragAccumulatedDy = 0;
                          });
                        }
                      : null,
                  onPanUpdate: (DragUpdateDetails details) {
                    if (widget.canMove) {
                      widget.onMoveByDeltaPx(details.delta.dx);
                      _dragAccumulatedDy += details.delta.dy;
                    }
                  },
                  onPanEnd: widget.canMove
                      ? (_) {
                          final int rowDelta =
                              (_dragAccumulatedDy / widget.trackRowHeight)
                                  .round();
                          if (rowDelta != 0) {
                            widget.onMoveToTrackByRowDelta?.call(rowDelta);
                          }
                          setState(_resetDrag);
                        }
                      : null,
                  onPanCancel: widget.canMove
                      ? () {
                          setState(_resetDrag);
                        }
                      : null,
                  onTap: () {
                    if (widget.canBladeSplit) {
                      widget.onSplitClipAtPlayhead(
                        trackId: widget.trackId,
                        clipId: widget.clip.id,
                        playheadMs: widget.playheadMs,
                      );
                      return;
                    }
                    if (widget.isTextClip &&
                        widget.isSelected &&
                        widget.onRenameTextClipRequested != null) {
                      widget.onRenameTextClipRequested!();
                      return;
                    }
                    widget.onSelect();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    child: Row(
                      children: <Widget>[
                        if (widget.isTextClip)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.subtitles_outlined,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        if (widget.width >= 24)
                          Expanded(
                            child: Text(
                              widget.displayLabel,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.cyberpunk.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: widget.isTextClip ? 11 : null,
                                  ),
                            ),
                          ),
                        if (showRenameIcon)
                          InkWell(
                            onTap: widget.onRenameTextClipRequested,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (showDeleteIcon)
                          InkWell(
                            onTap: widget.onRemove,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _TrimHandle(
              onDrag: widget.onTrimEndByDeltaPx,
              isLeft: false,
              enabled: widget.canTrim,
              width: handleWidth,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle({
    required this.onDrag,
    required this.isLeft,
    required this.enabled,
    this.width = 8,
  });

  final ValueChanged<double> onDrag;
  final bool isLeft;
  final bool enabled;
  final double width;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          if (enabled) {
            onDrag(details.delta.dx);
          }
        },
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: enabled ? 0.28 : 0.1),
            borderRadius: BorderRadius.horizontal(
              left: isLeft ? const Radius.circular(8) : Radius.zero,
              right: isLeft ? Radius.zero : const Radius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}
