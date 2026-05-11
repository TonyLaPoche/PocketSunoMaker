import 'track.dart';

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.fps,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.durationMs,
    required this.tracks,
  });

  final String id;
  final String name;
  final int fps;
  final int canvasWidth;
  final int canvasHeight;
  final int durationMs;
  final List<Track> tracks;

  Project copyWith({
    String? id,
    String? name,
    int? fps,
    int? canvasWidth,
    int? canvasHeight,
    int? durationMs,
    List<Track>? tracks,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      fps: fps ?? this.fps,
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
      durationMs: durationMs ?? this.durationMs,
      tracks: tracks ?? this.tracks,
    );
  }
}
