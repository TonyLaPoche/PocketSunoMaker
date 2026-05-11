class Clip {
  const Clip({
    required this.id,
    required this.assetPath,
    required this.timelineStartMs,
    required this.sourceInMs,
    required this.sourceOutMs,
  });

  final String id;
  final String assetPath;
  final int timelineStartMs;
  final int sourceInMs;
  final int sourceOutMs;

  int get durationMs => sourceOutMs - sourceInMs;

  Clip copyWith({
    String? id,
    String? assetPath,
    int? timelineStartMs,
    int? sourceInMs,
    int? sourceOutMs,
  }) {
    return Clip(
      id: id ?? this.id,
      assetPath: assetPath ?? this.assetPath,
      timelineStartMs: timelineStartMs ?? this.timelineStartMs,
      sourceInMs: sourceInMs ?? this.sourceInMs,
      sourceOutMs: sourceOutMs ?? this.sourceOutMs,
    );
  }
}
