import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preview_state.dart';

final NotifierProvider<PreviewController, PreviewState>
previewControllerProvider = NotifierProvider<PreviewController, PreviewState>(
  PreviewController.new,
);

class PreviewController extends Notifier<PreviewState> {
  static const int _tickMs = 33;
  Timer? _timer;
  bool _resumeAfterScrub = false;

  @override
  PreviewState build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return const PreviewState();
  }

  void setDuration(int durationMs) {
    final int normalized = durationMs < 0 ? 0 : durationMs;
    final int clampedPosition = state.currentPositionMs > normalized
        ? normalized
        : state.currentPositionMs;

    if (state.durationMs == normalized &&
        state.currentPositionMs == clampedPosition) {
      return;
    }

    if (normalized == 0) {
      _stopTimer();
      state = state.copyWith(
        isPlaying: false,
        isScrubbing: false,
        durationMs: 0,
        currentPositionMs: 0,
      );
      return;
    }

    state = state.copyWith(
      durationMs: normalized,
      currentPositionMs: clampedPosition,
    );
  }

  void togglePlayPause() {
    if (state.isScrubbing) {
      return;
    }
    if (state.durationMs <= 0) {
      return;
    }
    if (state.isPlaying) {
      pause();
      return;
    }
    play();
  }

  void play() {
    if (state.durationMs <= 0 || state.isPlaying || state.isScrubbing) {
      return;
    }
    state = state.copyWith(isPlaying: true);
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (_) {
      final int deltaMs = math.max(1, (_tickMs * state.playbackSpeed).round());
      final int next = state.currentPositionMs + deltaMs;
      if (next >= state.durationMs) {
        _stopTimer();
        state = state.copyWith(
          currentPositionMs: state.durationMs,
          isPlaying: false,
        );
        return;
      }
      state = state.copyWith(currentPositionMs: next);
    });
  }

  void setPlaybackSpeed(double speed) {
    final double safe = speed.clamp(0.25, 2.0);
    if ((state.playbackSpeed - safe).abs() < 0.001) {
      return;
    }
    state = state.copyWith(playbackSpeed: safe);
  }

  void pause() {
    if (!state.isPlaying) {
      return;
    }
    _stopTimer();
    state = state.copyWith(isPlaying: false);
  }

  void seekTo(int targetMs) {
    final int clamped = targetMs < 0
        ? 0
        : (targetMs > state.durationMs ? state.durationMs : targetMs);
    state = state.copyWith(currentPositionMs: clamped);
  }

  void beginScrub() {
    if (state.isScrubbing) {
      return;
    }
    _resumeAfterScrub = state.isPlaying;
    if (state.isPlaying) {
      pause();
    }
    state = state.copyWith(isScrubbing: true);
  }

  void endScrub() {
    if (!state.isScrubbing) {
      return;
    }
    state = state.copyWith(isScrubbing: false);
    if (_resumeAfterScrub) {
      _resumeAfterScrub = false;
      play();
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
