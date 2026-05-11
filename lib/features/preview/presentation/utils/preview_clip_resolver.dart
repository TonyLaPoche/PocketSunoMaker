import '../../../project/domain/entities/project.dart';
import '../../../project/domain/entities/track.dart';
import '../models/active_clip_info.dart';

ActiveClipInfo? findActiveClip({
  required Project project,
  required int positionMs,
  required TrackType type,
}) {
  ActiveClipInfo? best;
  int bestTrackIndex = -1;
  int bestStart = -1;

  for (final Track track in project.tracks) {
    if (track.type != type) {
      continue;
    }
    for (final clip in track.clips) {
      final int clipStart = clip.timelineStartMs;
      final int clipEnd = clip.timelineStartMs + clip.durationMs;
      if (positionMs < clipStart || positionMs > clipEnd) {
        continue;
      }

      final bool hasHigherTrackPriority = track.index > bestTrackIndex;
      final bool sameTrackButLaterStart =
          track.index == bestTrackIndex && clipStart > bestStart;

      if (best == null || hasHigherTrackPriority || sameTrackButLaterStart) {
        final int sourcePositionMs = clip.sourceInMs + (positionMs - clipStart);
        best = ActiveClipInfo(clip: clip, sourcePositionMs: sourcePositionMs);
        bestTrackIndex = track.index;
        bestStart = clipStart;
      }
    }
  }

  return best;
}
