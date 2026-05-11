import 'dart:io';

import '../../../project/domain/entities/clip.dart';
import '../../../project/domain/entities/export_preset.dart';
import '../../../project/domain/entities/project.dart';
import '../../../project/domain/entities/track.dart';

class FfmpegExportService {
  const FfmpegExportService();

  Future<void> exportProject({
    required Project project,
    required ExportPreset preset,
    required String outputPath,
  }) async {
    final Clip? videoClip = _firstClip(project, TrackType.video);
    final Clip? audioClip = _firstClip(project, TrackType.audio);
    if (videoClip == null && audioClip == null) {
      throw Exception('Aucun media exportable dans le projet.');
    }

    final List<String> args = <String>['-y'];
    if (videoClip != null) {
      _appendInputArgs(
        args,
        videoClip,
        loopStillImage: _isImage(videoClip.assetPath),
      );
    }
    if (audioClip != null) {
      _appendInputArgs(args, audioClip, loopStillImage: false);
    }

    if (videoClip != null) {
      args.addAll(<String>['-map', '0:v:0']);
      if (audioClip != null) {
        args.addAll(<String>['-map', '1:a:0']);
      } else {
        args.add('-an');
      }
    } else if (audioClip != null) {
      args.addAll(<String>[
        '-f',
        'lavfi',
        '-i',
        'color=c=black:s=${preset.width}x${preset.height}:d=${audioClip.durationMs / 1000}',
        '-map',
        '1:v:0',
        '-map',
        '0:a:0',
      ]);
    }

    args.addAll(<String>[
      '-vf',
      'scale=${preset.width}:${preset.height}:force_original_aspect_ratio=decrease,'
          'pad=${preset.width}:${preset.height}:(ow-iw)/2:(oh-ih)/2',
      '-r',
      preset.frameRate.toString(),
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-b:v',
      '${preset.videoBitrateKbps}k',
      '-c:a',
      'aac',
      '-b:a',
      '${preset.audioBitrateKbps}k',
      '-movflags',
      '+faststart',
      '-shortest',
      outputPath,
    ]);

    final ProcessResult result = await Process.run('ffmpeg', args).timeout(
      const Duration(minutes: 12),
      onTimeout: () => ProcessResult(0, -1, '', 'ffmpeg timeout'),
    );

    if (result.exitCode != 0) {
      final String stderr = (result.stderr ?? '').toString();
      final String shortError = stderr.length > 400
          ? '${stderr.substring(0, 400)}...'
          : stderr;
      throw Exception('Export FFmpeg echoue: $shortError');
    }
  }

  void _appendInputArgs(
    List<String> args,
    Clip clip, {
    required bool loopStillImage,
  }) {
    args.addAll(<String>['-ss', (clip.sourceInMs / 1000).toStringAsFixed(3)]);
    args.addAll(<String>['-t', (clip.durationMs / 1000).toStringAsFixed(3)]);
    if (loopStillImage) {
      args.addAll(<String>['-loop', '1']);
    }
    args.addAll(<String>['-i', clip.assetPath]);
  }

  Clip? _firstClip(Project project, TrackType type) {
    final List<Clip> clips = project.tracks
        .where((Track track) => track.type == type)
        .expand((Track track) => track.clips)
        .toList(growable: false);
    if (clips.isEmpty) {
      return null;
    }
    clips.sort(
      (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
    );
    return clips.first;
  }

  bool _isImage(String path) {
    final String lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.tiff');
  }
}
