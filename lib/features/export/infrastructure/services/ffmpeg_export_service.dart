import 'dart:io';
import 'dart:math' as math;

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
      _assertClipAccessible(videoClip);
      _appendInputArgs(
        args,
        videoClip,
        loopStillImage: _isImage(videoClip.assetPath),
      );
    }
    if (audioClip != null) {
      _assertClipAccessible(audioClip);
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
      _buildVideoFilter(project: project, preset: preset),
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

    final ProcessResult result;
    try {
      result = await Process.run('ffmpeg', args).timeout(
        const Duration(minutes: 12),
        onTimeout: () => ProcessResult(0, -1, '', 'ffmpeg timeout'),
      );
    } on ProcessException catch (error) {
      throw Exception(
        'Impossible de lancer ffmpeg (${error.message}). Verifie que ffmpeg est installe et accessible dans le PATH.',
      );
    }

    if (result.exitCode != 0) {
      final String stderr = (result.stderr ?? '').toString();
      if (_looksLikePermissionIssue(stderr)) {
        throw Exception(
          'Export impossible: un media source n est pas autorise par macOS. Reimporte les fichiers utilises dans ce projet puis relance l export.',
        );
      }
      final String shortError = stderr.length > 400
          ? '${stderr.substring(0, 400)}...'
          : stderr;
      throw Exception('Export FFmpeg echoue: $shortError');
    }
  }

  void _assertClipAccessible(Clip clip) {
    final File file = File(clip.assetPath);
    if (!file.existsSync()) {
      throw Exception('Media introuvable pour export: ${clip.assetPath}');
    }
    try {
      final RandomAccessFile raf = file.openSync(mode: FileMode.read);
      raf.closeSync();
    } on FileSystemException {
      throw Exception(
        'Media non accessible (permission macOS): ${clip.assetPath}. Reimporte ce media depuis PocketSunoMaker.',
      );
    }
  }

  bool _looksLikePermissionIssue(String stderr) {
    final String lower = stderr.toLowerCase();
    return lower.contains('operation not permitted') ||
        lower.contains('permission denied') ||
        lower.contains('not authorized') ||
        lower.contains('errno = 1');
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

  String _buildVideoFilter({
    required Project project,
    required ExportPreset preset,
  }) {
    final String baseScalePad =
        'scale=${preset.width}:${preset.height}:force_original_aspect_ratio=decrease,'
        'pad=${preset.width}:${preset.height}:(ow-iw)/2:(oh-ih)/2';
    final List<Clip> textClips =
        project.tracks
            .where((Track track) => track.type == TrackType.text)
            .expand((Track track) => track.clips)
            .toList(growable: false)
          ..sort(
            (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
          );
    if (textClips.isEmpty) {
      return baseScalePad;
    }
    final double sx = preset.width / project.canvasWidth;
    final double sy = preset.height / project.canvasHeight;
    final double fontScale = math.min(sx, sy);
    final List<String> drawTextFilters = <String>[];
    for (final Clip clip in textClips) {
      final String? rawText = clip.textContent?.trim();
      if (rawText == null || rawText.isEmpty) {
        continue;
      }
      final String text = _escapeDrawText(rawText);
      final String font = _escapeDrawText(clip.textFontFamily);
      final int fontSize = (clip.textFontSizePx * fontScale)
          .round()
          .clamp(10, 420)
          .toInt();
      final double xOffset = clip.textPosXPx * sx;
      final double yOffset = clip.textPosYPx * sy;
      final double start = clip.timelineStartMs / 1000;
      final double end = (clip.timelineStartMs + clip.durationMs) / 1000;
      final String fontColor = clip.textColorHex.replaceAll('#', '');
      final String boxColor = clip.textBackgroundHex.replaceAll('#', '');
      final int boxEnabled = clip.textShowBackground ? 1 : 0;
      drawTextFilters.add(
        "drawtext=text='$text':font='$font':fontsize=$fontSize:"
        "fontcolor=$fontColor:box=$boxEnabled:boxcolor=$boxColor@0.62:"
        "x=(w-text_w)/2+${xOffset.toStringAsFixed(2)}:"
        "y=(h-text_h)/2+${yOffset.toStringAsFixed(2)}:"
        "enable='between(t\\,${start.toStringAsFixed(3)}\\,${end.toStringAsFixed(3)})'",
      );
    }
    if (drawTextFilters.isEmpty) {
      return baseScalePad;
    }
    return <String>[baseScalePad, ...drawTextFilters].join(',');
  }

  String _escapeDrawText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll(':', r'\:')
        .replaceAll(',', r'\,')
        .replaceAll("'", r"\'")
        .replaceAll('%', r'\%');
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
