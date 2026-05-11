class PreviewState {
  const PreviewState({
    this.isPlaying = false,
    this.isScrubbing = false,
    this.currentPositionMs = 0,
    this.durationMs = 0,
  });

  final bool isPlaying;
  final bool isScrubbing;
  final int currentPositionMs;
  final int durationMs;

  PreviewState copyWith({
    bool? isPlaying,
    bool? isScrubbing,
    int? currentPositionMs,
    int? durationMs,
  }) {
    return PreviewState(
      isPlaying: isPlaying ?? this.isPlaying,
      isScrubbing: isScrubbing ?? this.isScrubbing,
      currentPositionMs: currentPositionMs ?? this.currentPositionMs,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}
