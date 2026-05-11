import 'clip.dart';

enum TrackType { video, audio, overlay, text }

class Track {
  const Track({
    required this.id,
    required this.type,
    required this.index,
    required this.clips,
  });

  final String id;
  final TrackType type;
  final int index;
  final List<Clip> clips;

  Track copyWith({String? id, TrackType? type, int? index, List<Clip>? clips}) {
    return Track(
      id: id ?? this.id,
      type: type ?? this.type,
      index: index ?? this.index,
      clips: clips ?? this.clips,
    );
  }
}
