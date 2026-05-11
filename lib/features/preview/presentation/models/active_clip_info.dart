import '../../../project/domain/entities/clip.dart';

class ActiveClipInfo {
  const ActiveClipInfo({
    required this.clip,
    required this.trackId,
    required this.sourcePositionMs,
  });

  final Clip clip;
  final String trackId;
  final int sourcePositionMs;
}
