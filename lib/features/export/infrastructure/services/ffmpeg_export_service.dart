import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../../project/domain/entities/clip.dart';
import '../../../project/domain/entities/export_preset.dart';
import '../../../project/domain/entities/project.dart';
import '../../../project/domain/entities/track.dart';

class FfmpegExportService {
  FfmpegExportService();

  Process? _runningProcess;
  bool _cancelRequested = false;

  void cancelCurrentExport() {
    _cancelRequested = true;
    _runningProcess?.kill(ProcessSignal.sigterm);
  }

  Future<void> exportProject({
    required Project project,
    required ExportPreset preset,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    _cancelRequested = false;
    final String ffmpegCommand = _resolveFfmpegCommand();
    final Clip? videoClip = _firstClip(project, TrackType.video);
    final Clip? audioClip = _firstClip(project, TrackType.audio);
    if (videoClip == null && audioClip == null) {
      throw Exception('Aucun media exportable dans le projet.');
    }

    final bool hasTextOverlays = _hasTextOverlays(project);
    final bool hasVisualEffectClips = _hasVisualEffectClips(project);
    final bool hasAudioEffectClips = _hasAudioEffectClips(project);
    final bool drawTextAvailable = hasTextOverlays
        ? await _isFilterAvailable(ffmpegCommand, 'drawtext')
        : true;
    if (hasTextOverlays && !drawTextAvailable) {
      throw Exception(
        'Export impossible: le filtre FFmpeg drawtext est absent. Installe ffmpeg-full (Homebrew) ou configure un FFmpeg avec libfreetype pour garantir le rendu texte a l export.',
      );
    }
    if (hasVisualEffectClips || hasAudioEffectClips) {
      throw Exception(
        'Export bloque: des clips Effets visuels/sonores sont presents mais leur rendu FFmpeg v1 n est pas encore active. Retire ces clips d effet avant export, ou attends la phase de parite export effets.',
      );
    }

    final List<String> args = <String>['-y', '-hide_banner'];
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
      '-progress',
      'pipe:1',
      '-nostats',
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
      result = await _runFfmpegWithProgress(
        command: ffmpegCommand,
        args: args,
        totalDurationMs: project.durationMs,
        onProgress: onProgress,
      );
    } on ProcessException catch (error) {
      throw Exception(
        'Impossible de lancer ffmpeg (${error.message}). Verifie que ffmpeg (ou ffmpeg-full) est installe et accessible.',
      );
    }

    if (result.exitCode != 0) {
      if (_cancelRequested) {
        throw Exception('Export annule par utilisateur.');
      }
      final String stderr = (result.stderr ?? '').toString();
      if (_looksLikePermissionIssue(stderr)) {
        throw Exception(
          'Export impossible: un media source n est pas autorise par macOS. Reimporte les fichiers utilises dans ce projet puis relance l export.',
        );
      }
      final String shortError = _compactError(stderr);
      throw Exception('Export FFmpeg echoue: $shortError');
    }
  }

  Future<ProcessResult> _runFfmpegWithProgress({
    required String command,
    required List<String> args,
    required int totalDurationMs,
    void Function(double progress)? onProgress,
  }) async {
    final Process process = await Process.start(command, args);
    _runningProcess = process;
    final StringBuffer stdoutBuffer = StringBuffer();
    final StringBuffer stderrBuffer = StringBuffer();
    double? lastProgress;
    final int safeTotalMs = totalDurationMs <= 0 ? 1 : totalDurationMs;

    final Future<void> stdoutFuture = process.stdout
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .forEach((String line) {
          stdoutBuffer.writeln(line);
          if (onProgress == null) {
            return;
          }
          if (line.startsWith('out_time_ms=')) {
            final String raw = line.substring('out_time_ms='.length).trim();
            final int? micros = int.tryParse(raw);
            if (micros == null) {
              return;
            }
            final int currentMs = (micros / 1000).round();
            final double progress = (currentMs / safeTotalMs).clamp(0.0, 1.0);
            if (lastProgress == null ||
                (progress - lastProgress!).abs() >= 0.002) {
              lastProgress = progress;
              onProgress(progress);
            }
          } else if (line == 'progress=end') {
            onProgress(1.0);
          }
        });

    final Future<void> stderrFuture = process.stderr
        .transform(systemEncoding.decoder)
        .forEach(stderrBuffer.write);

    try {
      final int exitCode = await process.exitCode.timeout(
        const Duration(minutes: 12),
        onTimeout: () {
          process.kill(ProcessSignal.sigterm);
          return -1;
        },
      );

      await Future.wait(<Future<void>>[stdoutFuture, stderrFuture]);
      return ProcessResult(
        process.pid,
        exitCode,
        stdoutBuffer.toString(),
        stderrBuffer.toString(),
      );
    } finally {
      if (identical(_runningProcess, process)) {
        _runningProcess = null;
      }
    }
  }

  String _resolveFfmpegCommand() {
    const List<String> preferredPaths = <String>[
      '/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg',
      '/usr/local/opt/ffmpeg-full/bin/ffmpeg',
    ];
    for (final String path in preferredPaths) {
      final File candidate = File(path);
      if (candidate.existsSync()) {
        return path;
      }
    }
    return 'ffmpeg';
  }

  bool _hasTextOverlays(Project project) {
    return project.tracks
        .where((Track track) => track.type == TrackType.text)
        .expand((Track track) => track.clips)
        .any((Clip clip) => (clip.textContent ?? '').trim().isNotEmpty);
  }

  bool _hasVisualEffectClips(Project project) {
    return project.tracks
        .where((Track track) => track.type == TrackType.visualEffect)
        .expand((Track track) => track.clips)
        .isNotEmpty;
  }

  bool _hasAudioEffectClips(Project project) {
    return project.tracks
        .where((Track track) => track.type == TrackType.audioEffect)
        .expand((Track track) => track.clips)
        .isNotEmpty;
  }

  Future<bool> _isFilterAvailable(
    String ffmpegCommand,
    String filterName,
  ) async {
    try {
      final ProcessResult result = await Process.run(ffmpegCommand, <String>[
        '-hide_banner',
        '-filters',
      ]).timeout(const Duration(seconds: 5));
      final String output = '${result.stdout ?? ''}\n${result.stderr ?? ''}'
          .toLowerCase();
      return output.contains(filterName.toLowerCase());
    } on Object {
      return false;
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
      final String? fontFile = _resolveFontFile(clip.textFontFamily);
      final int baseFontSize = (clip.textFontSizePx * fontScale)
          .round()
          .clamp(10, 420)
          .toInt();
      final double xOffset = clip.textPosXPx * sx;
      final double yOffset = clip.textPosYPx * sy;
      final double start = clip.timelineStartMs / 1000;
      final double end = (clip.timelineStartMs + clip.durationMs) / 1000;
      final String fontColor = clip.textColorHex.replaceAll('#', '');
      final String boxColor = clip.textBackgroundHex.replaceAll('#', '');
      final double textOpacity = clip.opacity.clamp(0.0, 1.0);
      final String boxOpacityStr = (textOpacity * 0.62).toStringAsFixed(3);
      final String alphaExpr = _buildTextAlphaExpression(
        clip: clip,
        start: start,
        end: end,
        baseOpacity: textOpacity,
      );
      final String yExpr = _buildTextYExpression(
        clip: clip,
        start: start,
        end: end,
        baseYOffset: yOffset,
      );
      final String fontSizeExpr = _buildTextFontSizeExpression(
        clip: clip,
        start: start,
        end: end,
        baseFontSize: baseFontSize,
      );
      final int boxEnabled = clip.textShowBackground ? 1 : 0;
      final String fontPart = fontFile == null
          ? ''
          : "fontfile='${_escapeDrawText(fontFile)}':";
      drawTextFilters.add(
        "drawtext=text='$text':$fontPart"
        "fontsize='$fontSizeExpr':"
        "fontcolor=$fontColor:box=$boxEnabled:boxcolor=$boxColor@$boxOpacityStr:"
        "alpha='$alphaExpr':"
        "x=(w-text_w)/2+${xOffset.toStringAsFixed(2)}:"
        "y='(h-text_h)/2+$yExpr':"
        "enable='between(t\\,${start.toStringAsFixed(3)}\\,${end.toStringAsFixed(3)})'",
      );
      if (clip.karaokeEnabled) {
        final String karaokeColor = clip.karaokeFillColorHex.replaceAll(
          '#',
          '',
        );
        final String karaokeProgressExpr = _buildKaraokeProgressExpression(
          clip: clip,
          start: start,
        );
        final String karaokeFillAlphaExpr =
            "($alphaExpr)*if(lt(x\\,((w-text_w)/2+${xOffset.toStringAsFixed(2)}+text_w*($karaokeProgressExpr)))\\,1\\,0)";
        drawTextFilters.add(
          "drawtext=text='$text':$fontPart"
          "fontsize='$fontSizeExpr':"
          "fontcolor=$karaokeColor:box=0:"
          "alpha='$karaokeFillAlphaExpr':"
          "x=(w-text_w)/2+${xOffset.toStringAsFixed(2)}:"
          "y='(h-text_h)/2+$yExpr':"
          "enable='between(t\\,${start.toStringAsFixed(3)}\\,${end.toStringAsFixed(3)})'",
        );
      }
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

  String _buildTextAlphaExpression({
    required Clip clip,
    required double start,
    required double end,
    required double baseOpacity,
  }) {
    String expr = baseOpacity.toStringAsFixed(3);
    final int clipDurationMs = clip.durationMs <= 0 ? 1 : clip.durationMs;
    final double entryDuration =
        (clip.textEntryDurationMs.clamp(0, clipDurationMs) / 1000.0).toDouble();
    final double exitDuration =
        (clip.textExitDurationMs.clamp(0, clipDurationMs) / 1000.0).toDouble();

    if (clip.hasEntryFade && entryDuration > 0) {
      final double entryEnd = start + entryDuration;
      expr =
          '($expr)*if(lt(t\\,${entryEnd.toStringAsFixed(3)})\\,max(0\\,min(1\\,(t-${start.toStringAsFixed(3)})/${entryDuration.toStringAsFixed(3)}))\\,1)';
    }
    if (clip.hasExitFade && exitDuration > 0) {
      final double exitStart = end - exitDuration;
      expr =
          '($expr)*if(gt(t\\,${exitStart.toStringAsFixed(3)})\\,max(0\\,min(1\\,(${end.toStringAsFixed(3)}-t)/${exitDuration.toStringAsFixed(3)}))\\,1)';
    }
    return expr;
  }

  String _buildTextYExpression({
    required Clip clip,
    required double start,
    required double end,
    required double baseYOffset,
  }) {
    String expr = baseYOffset.toStringAsFixed(2);
    final int clipDurationMs = clip.durationMs <= 0 ? 1 : clip.durationMs;
    final double entryDuration =
        (clip.textEntryDurationMs.clamp(0, clipDurationMs) / 1000.0).toDouble();
    final double exitDuration =
        (clip.textExitDurationMs.clamp(0, clipDurationMs) / 1000.0).toDouble();
    final String entryProgress =
        'max(0\\,min(1\\,(t-${start.toStringAsFixed(3)})/${entryDuration <= 0 ? 1 : entryDuration.toStringAsFixed(3)}))';
    final String exitProgress =
        'max(0\\,min(1\\,(${end.toStringAsFixed(3)}-t)/${exitDuration <= 0 ? 1 : exitDuration.toStringAsFixed(3)}))';
    final String entryEnd = (start + entryDuration).toStringAsFixed(3);
    final String exitStart = (end - exitDuration).toStringAsFixed(3);

    if (clip.hasEntrySlideUp && entryDuration > 0) {
      expr =
          '($expr)+if(lt(t\\,$entryEnd)\\,((1-$entryProgress)*${clip.textEntryOffsetPx.toStringAsFixed(2)})\\,0)';
    }
    if (clip.hasEntrySlideDown && entryDuration > 0) {
      expr =
          '($expr)-if(lt(t\\,$entryEnd)\\,((1-$entryProgress)*${clip.textEntryOffsetPx.toStringAsFixed(2)})\\,0)';
    }
    if (clip.hasExitSlideUp && exitDuration > 0) {
      expr =
          '($expr)-if(gt(t\\,$exitStart)\\,((1-$exitProgress)*${clip.textExitOffsetPx.toStringAsFixed(2)})\\,0)';
    }
    if (clip.hasExitSlideDown && exitDuration > 0) {
      expr =
          '($expr)+if(gt(t\\,$exitStart)\\,((1-$exitProgress)*${clip.textExitOffsetPx.toStringAsFixed(2)})\\,0)';
    }
    return expr;
  }

  String _buildTextFontSizeExpression({
    required Clip clip,
    required double start,
    required double end,
    required int baseFontSize,
  }) {
    String expr = baseFontSize.toString();
    final int clipDurationMs = clip.durationMs <= 0 ? 1 : clip.durationMs;
    final double entryDuration =
        (clip.textEntryDurationMs.clamp(0, clipDurationMs) / 1000.0).toDouble();
    final double exitDuration =
        (clip.textExitDurationMs.clamp(0, clipDurationMs) / 1000.0).toDouble();
    final String entryProgress =
        'max(0\\,min(1\\,(t-${start.toStringAsFixed(3)})/${entryDuration <= 0 ? 1 : entryDuration.toStringAsFixed(3)}))';
    final String exitProgress =
        'max(0\\,min(1\\,(${end.toStringAsFixed(3)}-t)/${exitDuration <= 0 ? 1 : exitDuration.toStringAsFixed(3)}))';
    final String entryEnd = (start + entryDuration).toStringAsFixed(3);
    final String exitStart = (end - exitDuration).toStringAsFixed(3);

    if (clip.hasEntryZoom && entryDuration > 0) {
      final double minScale = clip.textEntryScale.clamp(0.2, 1.0);
      expr =
          '($expr)*if(lt(t\\,$entryEnd)\\,($minScale+(1-$minScale)*$entryProgress)\\,1)';
    }
    if (clip.hasExitZoom && exitDuration > 0) {
      final double minScale = clip.textExitScale.clamp(0.2, 1.0);
      expr =
          '($expr)*if(gt(t\\,$exitStart)\\,($minScale+(1-$minScale)*$exitProgress)\\,1)';
    }
    return expr;
  }

  String _buildKaraokeProgressExpression({
    required Clip clip,
    required double start,
  }) {
    final double leadInSec = (clip.karaokeLeadInMs.clamp(0, 10000) / 1000.0)
        .toDouble();
    final double sweepSec =
        (clip.karaokeSweepDurationMs.clamp(300, 10000) / 1000.0).toDouble();
    final double startSec = start + leadInSec;
    return 'max(0\\,min(1\\,(t-${startSec.toStringAsFixed(3)})/${sweepSec.toStringAsFixed(3)}))';
  }

  String _compactError(String stderr) {
    final List<String> lines = stderr
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return 'erreur inconnue (stderr vide)';
    }
    final int start = math.max(0, lines.length - 8);
    final String compact = lines.sublist(start).join(' | ');
    return compact.length > 900 ? '${compact.substring(0, 900)}...' : compact;
  }

  String? _resolveFontFile(String fontFamily) {
    final String normalized = fontFamily.trim().toLowerCase();
    final Map<String, List<String>> candidatesByFamily = <String, List<String>>{
      'roboto': <String>['/System/Library/Fonts/Supplemental/Arial.ttf'],
      'arial': <String>['/System/Library/Fonts/Supplemental/Arial.ttf'],
      'helvetica': <String>['/System/Library/Fonts/Supplemental/Helvetica.ttf'],
      'avenir next': <String>[
        '/System/Library/Fonts/Supplemental/Avenir Next.ttc',
      ],
      'futura': <String>['/System/Library/Fonts/Supplemental/Futura.ttc'],
      'georgia': <String>['/System/Library/Fonts/Supplemental/Georgia.ttf'],
      'menlo': <String>['/System/Library/Fonts/Menlo.ttc'],
      'times new roman': <String>[
        '/System/Library/Fonts/Supplemental/Times New Roman.ttf',
      ],
      'courier new': <String>[
        '/System/Library/Fonts/Supplemental/Courier New.ttf',
      ],
    };
    final List<String> fallbackCandidates = <String>[
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Supplemental/Helvetica.ttf',
      '/Library/Fonts/Arial.ttf',
    ];
    final List<String> candidates =
        candidatesByFamily[normalized] ?? fallbackCandidates;
    for (final String path in <String>[...candidates, ...fallbackCandidates]) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
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
