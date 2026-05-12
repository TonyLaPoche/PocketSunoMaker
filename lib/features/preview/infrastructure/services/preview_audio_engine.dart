import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../../../project/domain/entities/clip.dart';
import '../../../project/domain/entities/project.dart';
import '../../../project/domain/entities/track.dart';
import '../../presentation/models/active_clip_info.dart';
import '../../presentation/utils/preview_clip_resolver.dart';

class PreviewAudioEngine {
  PreviewAudioEngine() : _player = AudioPlayer(), _fxPlayer = AudioPlayer();

  final AudioPlayer _player;
  final AudioPlayer _fxPlayer;

  String? _boundClipId;
  String? _boundPath;
  bool _isDisposed = false;
  final Set<String> _blockedPaths = <String>{};
  double _lastVolume = 1.0;
  double _lastSpeed = 1.0;
  int _lastStutterSeekMs = -999999;
  String? _beepPath;

  Future<void> synchronize({
    required Project? project,
    required int positionMs,
    required bool shouldPlay,
    required double volume,
    required double speed,
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
    final ActiveClipInfo? activeAudioFxClip = findActiveClip(
      project: project,
      positionMs: positionMs,
      type: TrackType.audioEffect,
    );

    if (activeAudioClip == null && activeAudioFxClip == null) {
      await _stopAndReset();
      return;
    }

    final AudioEffectType? audioEffectType = activeAudioFxClip?.clip.audioEffectType;
    await _syncFxPlayer(
      effectType: audioEffectType,
      shouldPlay: shouldPlay,
      intensity: activeAudioFxClip?.clip.effectIntensity ?? 0.6,
    );
    if (activeAudioClip == null) {
      await _stopMainPlayerOnly();
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
        _lastVolume = 1.0;
        _lastSpeed = 1.0;
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

      final double effectIntensity = (activeAudioFxClip?.clip.effectIntensity ?? 0.6)
          .clamp(0.1, 1.0);
      final double safeVolume = _resolveVolumeWithAudioEffect(
        baseVolume: volume.clamp(0.0, 2.0),
        effectType: audioEffectType,
        intensity: effectIntensity,
      );
      if ((_lastVolume - safeVolume).abs() > 0.001) {
        await _player.setVolume(safeVolume);
        _lastVolume = safeVolume;
      }
      final double safeSpeed = _resolveSpeedWithAudioEffect(
        baseSpeed: speed.clamp(0.25, 2.0),
        effectType: audioEffectType,
        intensity: effectIntensity,
      );
      if ((_lastSpeed - safeSpeed).abs() > 0.001) {
        await _player.setSpeed(safeSpeed);
        _lastSpeed = safeSpeed;
      }

      if (shouldPlay) {
        if (!_player.playing) {
          await _player.play();
        }
        if (audioEffectType == AudioEffectType.stutter) {
          _applyStutterIfNeeded(
            positionMs: positionMs,
            sourceMs: activeAudioClip.sourcePositionMs,
            intensity: effectIntensity,
          );
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
    await _stopMainPlayerOnly();
    try {
      if (_fxPlayer.playing) {
        await _fxPlayer.pause();
      }
    } catch (_) {}
  }

  Future<void> _stopMainPlayerOnly() async {
    _boundClipId = null;
    _boundPath = null;
    _lastVolume = 1.0;
    _lastSpeed = 1.0;
    _lastStutterSeekMs = -999999;
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
    await _fxPlayer.dispose();
  }

  Future<void> _syncFxPlayer({
    required AudioEffectType? effectType,
    required bool shouldPlay,
    required double intensity,
  }) async {
    if (effectType != AudioEffectType.censorBeep || !shouldPlay) {
      try {
        if (_fxPlayer.playing) {
          await _fxPlayer.pause();
        }
      } catch (_) {}
      return;
    }
    final String path = await _ensureBeepFile();
    try {
      if (_fxPlayer.audioSource == null) {
        await _fxPlayer.setFilePath(path);
        await _fxPlayer.setLoopMode(LoopMode.one);
      }
      await _fxPlayer.setVolume((0.20 + 0.75 * intensity).clamp(0.0, 1.0));
      if (!_fxPlayer.playing) {
        await _fxPlayer.play();
      }
    } catch (_) {}
  }

  double _resolveSpeedWithAudioEffect({
    required double baseSpeed,
    required AudioEffectType? effectType,
    required double intensity,
  }) {
    if (effectType == AudioEffectType.distortion) {
      return (baseSpeed * (1.05 + intensity * 0.25)).clamp(0.25, 2.0);
    }
    if (effectType == AudioEffectType.stutter) {
      return (baseSpeed * (1.0 + intensity * 0.05)).clamp(0.25, 2.0);
    }
    return baseSpeed;
  }

  double _resolveVolumeWithAudioEffect({
    required double baseVolume,
    required AudioEffectType? effectType,
    required double intensity,
  }) {
    if (effectType == AudioEffectType.distortion) {
      return (baseVolume * (0.78 + (1 - intensity) * 0.18)).clamp(0.0, 2.0);
    }
    return baseVolume;
  }

  Future<String> _ensureBeepFile() async {
    final String? existing = _beepPath;
    if (existing != null && File(existing).existsSync()) {
      return existing;
    }
    final Directory dir = Directory.systemTemp;
    final String path = '${dir.path}/pocketsunomaker_fx_beep.wav';
    final File file = File(path);
    if (!file.existsSync()) {
      await file.writeAsBytes(_buildSineBeepWav());
    }
    _beepPath = path;
    return path;
  }

  Uint8List _buildSineBeepWav() {
    const int sampleRate = 44100;
    const double durationSec = 0.22;
    const int channels = 1;
    const int bitsPerSample = 16;
    final int samples = (sampleRate * durationSec).round();
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;
    final int dataSize = samples * channels * bitsPerSample ~/ 8;
    final int fileSize = 36 + dataSize;
    final BytesBuilder bb = BytesBuilder();

    void wAscii(String s) => bb.add(s.codeUnits);
    void w16(int v) {
      final ByteData bd = ByteData(2)..setUint16(0, v, Endian.little);
      bb.add(bd.buffer.asUint8List());
    }

    void w32(int v) {
      final ByteData bd = ByteData(4)..setUint32(0, v, Endian.little);
      bb.add(bd.buffer.asUint8List());
    }

    wAscii('RIFF');
    w32(fileSize);
    wAscii('WAVE');
    wAscii('fmt ');
    w32(16);
    w16(1);
    w16(channels);
    w32(sampleRate);
    w32(byteRate);
    w16(blockAlign);
    w16(bitsPerSample);
    wAscii('data');
    w32(dataSize);

    const double freq = 1000.0;
    for (int i = 0; i < samples; i++) {
      final double t = i / sampleRate;
      final double env = t < 0.02 ? (t / 0.02) : (1 - ((t - 0.02) / 0.20));
      final double amp = env.clamp(0.0, 1.0) * 0.55;
      final int sample = (math.sin(2 * math.pi * freq * t) * 32767 * amp)
          .round()
          .clamp(-32768, 32767);
      w16(sample & 0xFFFF);
    }
    return bb.toBytes();
  }

  void _applyStutterIfNeeded({
    required int positionMs,
    required int sourceMs,
    required double intensity,
  }) {
    final int intervalMs = (220 - intensity * 120).round().clamp(70, 220);
    if ((positionMs - _lastStutterSeekMs).abs() < intervalMs) {
      return;
    }
    _lastStutterSeekMs = positionMs;
    final int backMs = (50 + intensity * 120).round();
    final int target = (sourceMs - backMs).clamp(0, sourceMs);
    unawaited(_player.seek(Duration(milliseconds: target)));
  }
}
