class PreviewState {
  const PreviewState({
    this.isPlaying = false,
    this.currentPositionMs = 0,
    this.durationMs = 0,
  });

  final bool isPlaying;
  final int currentPositionMs;
  final int durationMs;

  PreviewState copyWith({
    bool? isPlaying,
    int? currentPositionMs,
    int? durationMs,
  }) {
    return PreviewState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentPositionMs: currentPositionMs ?? this.currentPositionMs,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}
