import 'dart:io';

import 'package:just_audio/just_audio.dart';

import '../../../project/domain/entities/project.dart';
import '../../../project/domain/entities/track.dart';
import '../../presentation/models/active_clip_info.dart';
import '../../presentation/utils/preview_clip_resolver.dart';

class PreviewAudioEngine {
  PreviewAudioEngine() : _player = AudioPlayer();

  final AudioPlayer _player;

  String? _boundClipId;
  String? _boundPath;
  bool _isDisposed = false;
  final Set<String> _blockedPaths = <String>{};

  Future<void> synchronize({
    required Project? project,
    required int positionMs,
    required bool shouldPlay,
  }) async {
    if (_isDisposed) {
      return;
    }

    if (project == null) {
      await _stopAndReset();
      return;
    }

    final ActiveClipInfo? activeAudioClip = findActiveClip(
      project: project,
      positionMs: positionMs,
      type: TrackType.audio,
    );

    if (activeAudioClip == null) {
      await _stopAndReset();
      return;
    }

    final String clipId = activeAudioClip.clip.id;
    final String sourcePath = activeAudioClip.clip.assetPath;
    if (!File(sourcePath).existsSync()) {
      await _stopAndReset();
      return;
    }
    if (_blockedPaths.contains(sourcePath)) {
      await _stopAndReset();
      return;
    }

    final bool isNewClip = _boundClipId != clipId || _boundPath != sourcePath;
    try {
      if (isNewClip) {
        await _player.setFilePath(sourcePath);
        _boundClipId = clipId;
        _boundPath = sourcePath;
        await _player.seek(
          Duration(milliseconds: activeAudioClip.sourcePositionMs),
        );
      } else {
        final int currentMs = _player.position.inMilliseconds;
        final int desiredMs = activeAudioClip.sourcePositionMs;
        if ((currentMs - desiredMs).abs() > 120) {
          await _player.seek(Duration(milliseconds: desiredMs));
        }
      }

      if (shouldPlay) {
        if (!_player.playing) {
          await _player.play();
        }
      } else {
        if (_player.playing) {
          await _player.pause();
        }
      }
    } catch (_) {
      _blockedPaths.add(sourcePath);
      await _stopAndReset();
    }
  }

  Future<void> _stopAndReset() async {
    _boundClipId = null;
    _boundPath = null;
    try {
      if (_player.playing) {
        await _player.pause();
      }
    } catch (_) {
      // Ignore failures when backend can no longer access the file.
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _player.dispose();
  }
}
