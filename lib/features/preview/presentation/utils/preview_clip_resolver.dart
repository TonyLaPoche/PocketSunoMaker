import '../../../project/domain/entities/project.dart';
import '../../../project/domain/entities/track.dart';
import '../models/active_clip_info.dart';

ActiveClipInfo? findActiveClip({
  required Project project,
  required int positionMs,
  required TrackType type,
}) {
  final Iterable<Track> typedTracks = project.tracks.where(
    (Track track) => track.type == type,
  );
  for (final Track track in typedTracks) {
    for (final clip in track.clips) {
      final int clipStart = clip.timelineStartMs;
      final int clipEnd = clip.timelineStartMs + clip.durationMs;
      if (positionMs >= clipStart && positionMs <= clipEnd) {
        final int sourcePositionMs = clip.sourceInMs + (positionMs - clipStart);
        return ActiveClipInfo(clip: clip, sourcePositionMs: sourcePositionMs);
      }
    }
  }
  return null;
}
