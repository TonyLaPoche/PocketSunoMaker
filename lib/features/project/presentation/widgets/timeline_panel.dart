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
    required this.isPlaying,
    required this.onMoveClipByDelta,
    required this.onTrimClipStartByDelta,
    required this.onTrimClipEndByDelta,
    required this.onSplitClipAtPlayhead,
    required this.onRemoveClip,
    super.key,
  });

  final Project? project;
  final int playheadMs;
  final bool isPlaying;
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

  static const double _basePixelsPerSecond = 100;
  static const double _minZoom = 0.05;
  static const double _maxZoom = 3.0;
  static const double _rowHeight = 64;
  static const double _timelineStartLeft = 148;
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
    final double playheadLabelLeft = (playheadLeft - 26)
        .clamp(0.0, math.max(0.0, timelineWidth - 56))
        .toDouble();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _followPlayheadDuringPlayback(playheadLeft);
    });

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
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            zoomDivisions: ((_maxZoom - _minZoom) * 100).round(),
            snappingEnabled: snappingEnabled,
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
                zoomLevel = (zoomLevel + 0.02).clamp(_minZoom, _maxZoom);
              });
            },
            onZoomOut: () {
              setState(() {
                zoomLevel = (zoomLevel - 0.02).clamp(_minZoom, _maxZoom);
              });
            },
            onToggleSnapping: () {
              setState(() {
                snappingEnabled = !snappingEnabled;
              });
            },
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
                                        final bool isTrackMuted = mutedTrackIds
                                            .contains(track.id);
                                        final bool isTrackSolo = soloTrackIds
                                            .contains(track.id);
                                        final bool isTrackLocked =
                                            lockedTrackIds.contains(track.id);
                                        final bool isTrackDimmed =
                                            isTrackMuted ||
                                            (hasSoloTracks && !isTrackSolo);
                                        return _TimelineTrackRow(
                                          track: track,
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
                                          onToggleMute: () {
                                            setState(() {
                                              if (!mutedTrackIds.add(
                                                track.id,
                                              )) {
                                                mutedTrackIds.remove(track.id);
                                              }
                                            });
                                          },
                                          onToggleSolo: () {
                                            setState(() {
                                              if (!soloTrackIds.add(track.id)) {
                                                soloTrackIds.remove(track.id);
                                              }
                                            });
                                          },
                                          onToggleLock: () {
                                            setState(() {
                                              if (!lockedTrackIds.add(
                                                track.id,
                                              )) {
                                                lockedTrackIds.remove(track.id);
                                              }
                                            });
                                          },
                                          onSelectClip:
                                              ({
                                                required String trackId,
                                                required String clipId,
                                              }) {
                                                setState(() {
                                                  selectedClipId = clipId;
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
                          left: playheadLabelLeft,
                          top: 2,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: context.cyberpunk.neonBlue.withValues(
                                  alpha: 0.18,
                                ),
                                border: Border.all(
                                  color: context.cyberpunk.neonBlue.withValues(
                                    alpha: 0.65,
                                  ),
                                ),
                              ),
                              child: Text(
                                _formatTimelineTime(widget.playheadMs),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: context.cyberpunk.neonBlue,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ),
                        ),
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
    required this.onToggleMute,
    required this.onToggleSolo,
    required this.onToggleLock,
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
  final bool snappingEnabled;
  final bool isTrackMuted;
  final bool isTrackSolo;
  final bool isTrackLocked;
  final bool dimmed;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSolo;
  final VoidCallback onToggleLock;
  final void Function({required String trackId, required String clipId})
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
  final void Function({required String trackId, required String clipId})
  onRemoveClip;
  static const double _trackHeaderWidth = 148;

  @override
  Widget build(BuildContext context) {
    final bool isSelectedTrack =
        selectedClipId != null &&
        track.clips.any((Clip clip) => clip.id == selectedClipId);
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
                        Text(
                          '${track.type.name.toUpperCase()} ${track.index + 1}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.cyberpunk.neonBlue,
                                fontWeight: FontWeight.w700,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
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
            final double left =
                _trackHeaderWidth +
                (clip.timelineStartMs / 1000) * pixelsPerSecond;
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
    required this.dimmed,
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
  final bool dimmed;
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
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: Container(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          p.basename(clip.assetPath),
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
