import 'clip.dart';

enum TrackType { video, audio, overlay, text, visualEffect, audioEffect }

class Track {
  const Track({
    required this.id,
    required this.type,
    required this.index,
    required this.clips,
    this.name,
  });

  final String id;
  final TrackType type;
  final int index;
  final List<Clip> clips;
  final String? name;

  Track copyWith({
    String? id,
    TrackType? type,
    int? index,
    List<Clip>? clips,
    String? name,
  }) {
    return Track(
      id: id ?? this.id,
      type: type ?? this.type,
      index: index ?? this.index,
      clips: clips ?? this.clips,
      name: name ?? this.name,
    );
  }
}
