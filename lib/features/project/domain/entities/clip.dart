class Clip {
  const Clip({
    required this.id,
    required this.assetPath,
    required this.timelineStartMs,
    required this.sourceInMs,
    required this.sourceOutMs,
    this.opacity = 1.0,
    this.speed = 1.0,
    this.volume = 1.0,
    this.scale = 1.0,
    this.rotationDeg = 0.0,
  });

  final String id;
  final String assetPath;
  final int timelineStartMs;
  final int sourceInMs;
  final int sourceOutMs;
  final double opacity;
  final double speed;
  final double volume;
  final double scale;
  final double rotationDeg;

  int get durationMs => sourceOutMs - sourceInMs;

  Clip copyWith({
    String? id,
    String? assetPath,
    int? timelineStartMs,
    int? sourceInMs,
    int? sourceOutMs,
    double? opacity,
    double? speed,
    double? volume,
    double? scale,
    double? rotationDeg,
  }) {
    return Clip(
      id: id ?? this.id,
      assetPath: assetPath ?? this.assetPath,
      timelineStartMs: timelineStartMs ?? this.timelineStartMs,
      sourceInMs: sourceInMs ?? this.sourceInMs,
      sourceOutMs: sourceOutMs ?? this.sourceOutMs,
      opacity: opacity ?? this.opacity,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      scale: scale ?? this.scale,
      rotationDeg: rotationDeg ?? this.rotationDeg,
    );
  }
}
