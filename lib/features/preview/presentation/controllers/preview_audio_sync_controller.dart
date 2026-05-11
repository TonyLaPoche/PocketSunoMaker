import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../project/domain/entities/project.dart';
import '../../infrastructure/services/preview_audio_engine.dart';

final Provider<PreviewAudioEngine> previewAudioEngineProvider =
    Provider<PreviewAudioEngine>((Ref ref) {
      final PreviewAudioEngine engine = PreviewAudioEngine();
      ref.onDispose(() async {
        await engine.dispose();
      });
      return engine;
    });

final Provider<PreviewAudioSyncController> previewAudioSyncControllerProvider =
    Provider<PreviewAudioSyncController>((Ref ref) {
      return PreviewAudioSyncController(ref.read(previewAudioEngineProvider));
    });

class PreviewAudioSyncController {
  PreviewAudioSyncController(this._engine);

  final PreviewAudioEngine _engine;

  Future<void> synchronize({
    required Project? project,
    required int positionMs,
    required bool shouldPlay,
    required double volume,
    required double speed,
  }) {
    return _engine.synchronize(
      project: project,
      positionMs: positionMs,
      shouldPlay: shouldPlay,
      volume: volume,
      speed: speed,
    );
  }
}
