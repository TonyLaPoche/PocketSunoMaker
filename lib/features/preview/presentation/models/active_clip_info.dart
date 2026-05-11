import '../../../project/domain/entities/clip.dart';

class ActiveClipInfo {
  const ActiveClipInfo({required this.clip, required this.sourcePositionMs});

  final Clip clip;
  final int sourcePositionMs;
}
