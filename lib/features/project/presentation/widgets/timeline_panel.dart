import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../app/theme/cyberpunk_palette.dart';
import '../../domain/entities/clip.dart';
import '../../domain/entities/project.dart';
import '../../domain/entities/track.dart';

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({
    required this.project,
    required this.onMoveClipByDelta,
    required this.onRemoveClip,
    super.key,
  });

  final Project? project;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
  })
  onMoveClipByDelta;
  final void Function({required String trackId, required String clipId})
  onRemoveClip;

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  String? selectedClipId;

  static const double _pixelsPerSecond = 100;
  static const double _rowHeight = 64;

  @override
  Widget build(BuildContext context) {
    if (widget.project == null) {
      return const Center(
        child: Text(
          'Timeline inactive: cree un projet pour commencer le montage.',
        ),
      );
    }

    final int durationMs = math.max(widget.project!.durationMs, 30000);
    final double timelineWidth = (durationMs / 1000) * _pixelsPerSecond + 200;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cyberpunk.border),
        color: context.cyberpunk.bgSecondary,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: timelineWidth,
          child: Column(
            children: <Widget>[
              _TimelineRuler(
                width: timelineWidth,
                durationMs: durationMs,
                pixelsPerSecond: _pixelsPerSecond,
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
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final Track track = widget.project!.tracks[index];
                      return _TimelineTrackRow(
                        track: track,
                        rowHeight: _rowHeight,
                        pixelsPerSecond: _pixelsPerSecond,
                        selectedClipId: selectedClipId,
                        onSelectClip: (String clipId) {
                          setState(() {
                            selectedClipId = clipId;
                          });
                        },
                        onMoveClipByDelta: widget.onMoveClipByDelta,
                        onRemoveClip: widget.onRemoveClip,
                      );
                    },
                  ),
                ),
            ],
          ),
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
    required this.selectedClipId,
    required this.onSelectClip,
    required this.onMoveClipByDelta,
    required this.onRemoveClip,
  });

  final Track track;
  final double rowHeight;
  final double pixelsPerSecond;
  final String? selectedClipId;
  final ValueChanged<String> onSelectClip;
  final void Function({
    required String trackId,
    required String clipId,
    required int deltaMs,
  })
  onMoveClipByDelta;
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
                isSelected: selectedClipId == clip.id,
                onSelect: () => onSelectClip(clip.id),
                onRemove: () =>
                    onRemoveClip(trackId: track.id, clipId: clip.id),
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
    required this.isSelected,
    required this.onSelect,
    required this.onRemove,
    required this.onMoveByDeltaPx,
  });

  final Clip clip;
  final double width;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onRemove;
  final ValueChanged<double> onMoveByDeltaPx;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        onMoveByDeltaPx(details.delta.dx);
      },
      onTap: onSelect,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
            if (isSelected)
              InkWell(
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
