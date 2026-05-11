import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
    required this.onMoveClipByDelta,
    required this.onTrimClipStartByDelta,
    required this.onTrimClipEndByDelta,
    required this.onSplitClipAtPlayhead,
    required this.onRemoveClip,
    super.key,
  });

  final Project? project;
  final int playheadMs;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
  })
  onMoveClipByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
  })
  onTrimClipStartByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
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

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  String? selectedClipId;
  String? selectedTrackId;
  TimelineEditTool activeTool = TimelineEditTool.select;
  double zoomLevel = 1.0;
  double _lastPanZoomScale = 1.0;
  final List<int> markersMs = <int>[];
  final ScrollController horizontalScrollController = ScrollController();

  static const double _basePixelsPerSecond = 100;
  static const double _minZoom = 0.01;
  static const double _maxZoom = 3.0;
  static const double _rowHeight = 64;
  static const double _timelineStartLeft = 88;

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
    final ({String trackId, Clip clip})? selectedClipRef = _resolveSelectedClip(
      widget.project!,
    );

    return Container(
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
            markerCount: markersMs.length,
            onToolSelected: (TimelineEditTool tool) {
              setState(() {
                activeTool = tool;
              });
            },
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
                zoomLevel = (zoomLevel + 0.15).clamp(_minZoom, _maxZoom);
              });
            },
            onZoomOut: () {
              setState(() {
                zoomLevel = (zoomLevel - 0.15).clamp(_minZoom, _maxZoom);
              });
            },
          ),
          if (selectedClipRef != null)
            _SelectedClipToolbar(
              clip: selectedClipRef.clip,
              activeTool: activeTool,
              onToolSelected: (TimelineEditTool tool) {
                setState(() {
                  activeTool = tool;
                });
              },
              onStretchShorter: () {
                widget.onTrimClipEndByDelta(
                  trackId: selectedClipRef.trackId,
                  clipId: selectedClipRef.clip.id,
                  deltaMs: -500,
                );
              },
              onStretchLonger: () {
                widget.onTrimClipEndByDelta(
                  trackId: selectedClipRef.trackId,
                  clipId: selectedClipRef.clip.id,
                  deltaMs: 500,
                );
              },
              onDelete: () {
                widget.onRemoveClip(
                  trackId: selectedClipRef.trackId,
                  clipId: selectedClipRef.clip.id,
                );
                setState(() {
                  selectedClipId = null;
                  selectedTrackId = null;
                });
              },
            ),
          Expanded(
            child: Listener(
              onPointerPanZoomStart: (_) {
                _lastPanZoomScale = 1.0;
              },
              onPointerPanZoomUpdate: (PointerPanZoomUpdateEvent event) {
                final double scaleDelta = event.scale - _lastPanZoomScale;
                _lastPanZoomScale = event.scale;
                if (scaleDelta.abs() > 0.001) {
                  setState(() {
                    final double next = zoomLevel + (scaleDelta * 1.2);
                    zoomLevel = next.clamp(_minZoom, _maxZoom);
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
                    onHorizontalDragUpdate: activeTool == TimelineEditTool.hand
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
                            _TimelineRuler(
                              width: timelineWidth,
                              durationMs: durationMs,
                              pixelsPerSecond: pixelsPerSecond,
                            ),
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
                                        return _TimelineTrackRow(
                                          track: track,
                                          rowHeight: _rowHeight,
                                          pixelsPerSecond: pixelsPerSecond,
                                          playheadMs: widget.playheadMs,
                                          activeTool: activeTool,
                                          selectedClipId: selectedClipId,
                                          onSelectClip:
                                              ({
                                                required String trackId,
                                                required String clipId,
                                              }) {
                                                setState(() {
                                                  selectedClipId = clipId;
                                                  selectedTrackId = trackId;
                                                });
                                              },
                                          onMoveClipByDelta:
                                              widget.onMoveClipByDelta,
                                          onTrimClipStartByDelta:
                                              widget.onTrimClipStartByDelta,
                                          onTrimClipEndByDelta:
                                              widget.onTrimClipEndByDelta,
                                          onSplitClipAtPlayhead:
                                              widget.onSplitClipAtPlayhead,
                                          onRemoveClip:
                                              ({
                                                required String trackId,
                                                required String clipId,
                                              }) {
                                                widget.onRemoveClip(
                                                  trackId: trackId,
                                                  clipId: clipId,
                                                );
                                                if (selectedClipId == clipId) {
                                                  setState(() {
                                                    selectedClipId = null;
                                                    selectedTrackId = null;
                                                  });
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
                          left: playheadLeft,
                          top: 0,
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
    );
  }

  ({String trackId, Clip clip})? _resolveSelectedClip(Project project) {
    if (selectedClipId == null || selectedTrackId == null) {
      return null;
    }
    for (final Track track in project.tracks) {
      if (track.id != selectedTrackId) {
        continue;
      }
      for (final Clip clip in track.clips) {
        if (clip.id == selectedClipId) {
          return (trackId: track.id, clip: clip);
        }
      }
    }
    return null;
  }
}

class _TimelineToolbar extends StatelessWidget {
  const _TimelineToolbar({
    required this.activeTool,
    required this.zoomLevel,
    required this.markerCount,
    required this.onToolSelected,
    required this.onAddMarker,
    required this.onClearMarkers,
    required this.onZoomChanged,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final TimelineEditTool activeTool;
  final double zoomLevel;
  final int markerCount;
  final ValueChanged<TimelineEditTool> onToolSelected;
  final VoidCallback onAddMarker;
  final VoidCallback onClearMarkers;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

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
              min: 0.01,
              max: 3.0,
              divisions: 299,
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

class _SelectedClipToolbar extends StatelessWidget {
  const _SelectedClipToolbar({
    required this.clip,
    required this.activeTool,
    required this.onToolSelected,
    required this.onStretchShorter,
    required this.onStretchLonger,
    required this.onDelete,
  });

  final Clip clip;
  final TimelineEditTool activeTool;
  final ValueChanged<TimelineEditTool> onToolSelected;
  final VoidCallback onStretchShorter;
  final VoidCallback onStretchLonger;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: context.cyberpunk.bgPrimary.withValues(alpha: 0.8),
        border: Border.all(color: context.cyberpunk.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            'Selection: ${p.basename(clip.assetPath)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.cyberpunk.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'Duree: ${(clip.durationMs / 1000).toStringAsFixed(2)}s',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.cyberpunk.textMuted),
          ),
          _InlineToolChip(
            label: 'Selection',
            icon: Icons.ads_click_outlined,
            isActive: activeTool == TimelineEditTool.select,
            onTap: () => onToolSelected(TimelineEditTool.select),
          ),
          _InlineToolChip(
            label: 'Trim',
            icon: Icons.tune,
            isActive: activeTool == TimelineEditTool.trim,
            onTap: () => onToolSelected(TimelineEditTool.trim),
          ),
          TextButton.icon(
            onPressed: onStretchShorter,
            icon: const Icon(Icons.remove),
            label: const Text('Raccourcir 0.5s'),
          ),
          TextButton.icon(
            onPressed: onStretchLonger,
            icon: const Icon(Icons.add),
            label: const Text('Etirer 0.5s'),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer clip',
          ),
        ],
      ),
    );
  }
}

class _InlineToolChip extends StatelessWidget {
  const _InlineToolChip({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? context.cyberpunk.neonBlue
                : context.cyberpunk.border,
          ),
          color: isActive
              ? context.cyberpunk.neonBlue.withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14),
            const SizedBox(width: 5),
            Text(label),
          ],
        ),
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

class _TimelineRuler extends StatelessWidget {
  const _TimelineRuler({
    required this.width,
    required this.durationMs,
    required this.pixelsPerSecond,
  });

  final double width;
  final int durationMs;
  final double pixelsPerSecond;

  @override
  Widget build(BuildContext context) {
    final int seconds = (durationMs / 1000).ceil();
    return SizedBox(
      height: 34,
      width: width,
      child: Stack(
        children: List<Widget>.generate(seconds + 1, (int second) {
          final double left = second * pixelsPerSecond;
          return Positioned(
            left: left,
            top: 0,
            bottom: 0,
            child: Row(
              children: <Widget>[
                Container(width: 1, color: context.cyberpunk.border),
                const SizedBox(width: 4),
                if (second % 2 == 0)
                  Text(
                    '${second}s',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.cyberpunk.textMuted,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _TimelineTrackRow extends StatelessWidget {
  const _TimelineTrackRow({
    required this.track,
    required this.rowHeight,
    required this.pixelsPerSecond,
    required this.playheadMs,
    required this.activeTool,
    required this.selectedClipId,
    required this.onSelectClip,
    required this.onMoveClipByDelta,
    required this.onTrimClipStartByDelta,
    required this.onTrimClipEndByDelta,
    required this.onSplitClipAtPlayhead,
    required this.onRemoveClip,
  });

  final Track track;
  final double rowHeight;
  final double pixelsPerSecond;
  final int playheadMs;
  final TimelineEditTool activeTool;
  final String? selectedClipId;
  final void Function({required String trackId, required String clipId})
  onSelectClip;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
  })
  onMoveClipByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
  })
  onTrimClipStartByDelta;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 88,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${track.type.name} #${track.index}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.cyberpunk.neonBlue,
                        fontWeight: FontWeight.w700,
                      ),
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
            final double left =
                88 + (clip.timelineStartMs / 1000) * pixelsPerSecond;
            final double width = math.max(
              (clip.durationMs / 1000) * pixelsPerSecond,
              42,
            );
            return Positioned(
              left: left,
              top: 10,
              child: _TimelineClipWidget(
                clip: clip,
                width: width,
                playheadMs: playheadMs,
                trackId: track.id,
                isSelected: selectedClipId == clip.id,
                canTrim:
                    activeTool == TimelineEditTool.trim ||
                    selectedClipId == clip.id,
                canMove: activeTool == TimelineEditTool.select,
                canDelete: activeTool == TimelineEditTool.select,
                canBladeSplit: activeTool == TimelineEditTool.blade,
                onSelect: () =>
                    onSelectClip(trackId: track.id, clipId: clip.id),
                onRemove: () =>
                    onRemoveClip(trackId: track.id, clipId: clip.id),
                onSplitClipAtPlayhead: onSplitClipAtPlayhead,
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

class _TimelineClipWidget extends StatelessWidget {
  const _TimelineClipWidget({
    required this.clip,
    required this.width,
    required this.playheadMs,
    required this.trackId,
    required this.isSelected,
    required this.canTrim,
    required this.canMove,
    required this.canDelete,
    required this.canBladeSplit,
    required this.onSelect,
    required this.onRemove,
    required this.onSplitClipAtPlayhead,
    required this.onTrimStartByDeltaPx,
    required this.onTrimEndByDeltaPx,
    required this.onMoveByDeltaPx,
  });

  final Clip clip;
  final double width;
  final int playheadMs;
  final String trackId;
  final bool isSelected;
  final bool canTrim;
  final bool canMove;
  final bool canDelete;
  final bool canBladeSplit;
  final VoidCallback onSelect;
  final VoidCallback onRemove;
  final void Function({
    required String trackId,
    required String clipId,
    required int playheadMs,
  })
  onSplitClipAtPlayhead;
  final ValueChanged<double> onTrimStartByDeltaPx;
  final ValueChanged<double> onTrimEndByDeltaPx;
  final ValueChanged<double> onMoveByDeltaPx;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: <Color>[
            context.cyberpunk.neonPink.withValues(alpha: 0.85),
            context.cyberpunk.neonViolet.withValues(alpha: 0.85),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: context.cyberpunk.neonPink.withValues(alpha: 0.24),
            blurRadius: 12,
          ),
          if (isSelected)
            BoxShadow(
              color: context.cyberpunk.neonBlue.withValues(alpha: 0.35),
              blurRadius: 16,
              spreadRadius: 1.5,
            ),
        ],
      ),
      child: Row(
        children: <Widget>[
          _TrimHandle(
            onDrag: onTrimStartByDeltaPx,
            isLeft: true,
            enabled: canTrim,
          ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (DragUpdateDetails details) {
                if (canMove) {
                  onMoveByDeltaPx(details.delta.dx);
                }
              },
              onTap: () {
                if (canBladeSplit) {
                  onSplitClipAtPlayhead(
                    trackId: trackId,
                    clipId: clip.id,
                    playheadMs: playheadMs,
                  );
                  return;
                }
                onSelect();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        p.basename(clip.assetPath),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.cyberpunk.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isSelected && canDelete)
                      InkWell(
                        onTap: onRemove,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _TrimHandle(
            onDrag: onTrimEndByDeltaPx,
            isLeft: false,
            enabled: canTrim,
          ),
        ],
      ),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle({
    required this.onDrag,
    required this.isLeft,
    required this.enabled,
  });

  final ValueChanged<double> onDrag;
  final bool isLeft;
  final bool enabled;

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
          width: 8,
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
