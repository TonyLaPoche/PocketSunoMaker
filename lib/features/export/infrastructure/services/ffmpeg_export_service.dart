import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
    if (hasAudioEffectClips && audioClip == null) {
      throw Exception(
        'Export bloque: des clips Effets sonores sont presents mais aucun media audio n est disponible pour appliquer ces effets.',
      );
    }

    final List<String> args = <String>['-y', '-hide_banner'];
    if (videoClip != null) {
      _assertClipAccessible(videoClip);
      _appendInputArgs(
        args,
        videoClip,
        loopStillImage: _isImage(videoClip.assetPath),
        stillImageFrameRate: preset.frameRate,
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
    final int outputDurationMs =
        videoClip?.durationMs ?? audioClip?.durationMs ?? project.durationMs;
    final String? audioFilter = audioClip == null
        ? null
        : _buildAudioFilter(
            project: project,
            timelineOriginMs: audioClip.timelineStartMs,
          );
    if (audioClip != null) {
      if (audioFilter != null && audioFilter.isNotEmpty) {
        args.addAll(<String>['-af', audioFilter]);
      }
    }
    final String videoFilter = _buildVideoFilter(
      project: project,
      preset: preset,
      includeVisualEffects: hasVisualEffectClips,
      timelineOriginMs: videoClip?.timelineStartMs ?? 0,
      sourceIsStillImage: videoClip != null && _isImage(videoClip.assetPath),
      outputDurationMs: outputDurationMs,
    );

    args.addAll(<String>[
      '-progress',
      'pipe:1',
      '-nostats',
      '-vf',
      videoFilter,
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
    final String debugPath = _debugFilePath(outputPath);
    await _writeExportDebugSnapshot(
      debugPath: debugPath,
      phase: 'before_run',
      project: project,
      preset: preset,
      command: ffmpegCommand,
      args: args,
      outputPath: outputPath,
      timelineOriginMs: videoClip?.timelineStartMs ?? 0,
      outputDurationMs: outputDurationMs,
      videoFilter: videoFilter,
      audioFilter: audioFilter,
    );

    final ProcessResult result;
    try {
      result = await _runFfmpegWithProgress(
        command: ffmpegCommand,
        args: args,
        totalDurationMs: project.durationMs,
        onProgress: onProgress,
      );
    } on ProcessException catch (error) {
      await _writeExportDebugSnapshot(
        debugPath: debugPath,
        phase: 'launch_error',
        project: project,
        preset: preset,
        command: ffmpegCommand,
        args: args,
        outputPath: outputPath,
        timelineOriginMs: videoClip?.timelineStartMs ?? 0,
        outputDurationMs: outputDurationMs,
        videoFilter: videoFilter,
        audioFilter: audioFilter,
        launchError: error,
      );
      throw Exception(
        'Impossible de lancer ffmpeg (${error.message}). Verifie que ffmpeg (ou ffmpeg-full) est installe et accessible.',
      );
    }
    await _writeExportDebugSnapshot(
      debugPath: debugPath,
      phase: 'after_run',
      project: project,
      preset: preset,
      command: ffmpegCommand,
      args: args,
      outputPath: outputPath,
      timelineOriginMs: videoClip?.timelineStartMs ?? 0,
      outputDurationMs: outputDurationMs,
      videoFilter: videoFilter,
      audioFilter: audioFilter,
      result: result,
    );

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

  Future<void> exportProjectFromPreviewFrames({
    required Project project,
    required ExportPreset preset,
    required String outputPath,
    required Future<Uint8List?> Function(int positionMs) renderFramePngAt,
    void Function(double progress)? onProgress,
  }) async {
    _cancelRequested = false;
    final String ffmpegCommand = _resolveFfmpegCommand();
    final Clip? audioClip = _firstClip(project, TrackType.audio);
    final int durationMs = math.max(1, project.durationMs);
    final int fps = preset.frameRate <= 0 ? 30 : preset.frameRate;
    final int totalFrames = math.max(1, ((durationMs / 1000.0) * fps).ceil());
    final String debugPath = _debugFilePath(outputPath);
    final _HardwareProfile hardwareProfile = await _scanHardwareProfile();
    final Directory frameDir = Directory('$outputPath.preview-frames');
    if (frameDir.existsSync()) {
      frameDir.deleteSync(recursive: true);
    }
    frameDir.createSync(recursive: true);

    await _appendDebugNote(
      debugPath,
      'frame_export_profile=${hardwareProfile.mode} '
      'cpu=${hardwareProfile.cpuCount} '
      'mem_gb=${hardwareProfile.memoryGb.toStringAsFixed(1)} '
      'delay_ms=${hardwareProfile.interFrameDelayMs}',
    );
    await _writeExportDebugSnapshot(
      debugPath: debugPath,
      phase: 'before_frame_render',
      project: project,
      preset: preset,
      command: ffmpegCommand,
      args: const <String>[],
      outputPath: outputPath,
      timelineOriginMs: 0,
      outputDurationMs: durationMs,
      videoFilter: '<preview_frame_renderer>',
      audioFilter: '<none>',
    );

    try {
      for (int i = 0; i < totalFrames; i++) {
        if (_cancelRequested) {
          throw Exception('Export annule par utilisateur.');
        }
        final int positionMs = math.min(
          durationMs - 1,
          ((i * 1000.0) / fps).round(),
        );
        final Uint8List? pngBytes = await renderFramePngAt(positionMs);
        if (pngBytes == null || pngBytes.isEmpty) {
          throw Exception(
            'Capture preview impossible a ${positionMs}ms (frame ${i + 1}/$totalFrames).',
          );
        }
        final String fileName = 'frame_${i.toString().padLeft(6, '0')}.png';
        final File outputFile = File('${frameDir.path}/$fileName');
        await outputFile.writeAsBytes(pngBytes, flush: false);
        if (onProgress != null) {
          onProgress((i + 1) / totalFrames * 0.85);
        }
        if (hardwareProfile.interFrameDelayMs > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: hardwareProfile.interFrameDelayMs),
          );
        }
      }

      final List<String> args = <String>[
        '-y',
        '-hide_banner',
        '-framerate',
        fps.toString(),
        '-i',
        '${frameDir.path}/frame_%06d.png',
      ];
      if (audioClip != null) {
        _assertClipAccessible(audioClip);
        args.addAll(<String>[
          '-ss',
          (audioClip.sourceInMs / 1000).toStringAsFixed(3),
          '-t',
          (durationMs / 1000).toStringAsFixed(3),
          '-i',
          audioClip.assetPath,
          '-map',
          '0:v:0',
          '-map',
          '1:a:0',
        ]);
      } else {
        args.addAll(<String>['-map', '0:v:0', '-an']);
      }
      args.addAll(<String>[
        '-progress',
        'pipe:1',
        '-nostats',
        '-r',
        fps.toString(),
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-b:v',
        '${preset.videoBitrateKbps}k',
        if (audioClip != null) ...<String>[
          '-c:a',
          'aac',
          '-b:a',
          '${preset.audioBitrateKbps}k',
        ],
        '-movflags',
        '+faststart',
        '-shortest',
        outputPath,
      ]);

      await _writeExportDebugSnapshot(
        debugPath: debugPath,
        phase: 'before_run_from_frames',
        project: project,
        preset: preset,
        command: ffmpegCommand,
        args: args,
        outputPath: outputPath,
        timelineOriginMs: 0,
        outputDurationMs: durationMs,
        videoFilter: '<assembled_from_preview_frames>',
        audioFilter: '<none>',
      );

      final ProcessResult result = await _runFfmpegWithProgress(
        command: ffmpegCommand,
        args: args,
        totalDurationMs: durationMs,
        onProgress: onProgress == null
            ? null
            : (double progress) {
                final double mapped = 0.85 + progress * 0.15;
                onProgress(mapped.clamp(0.0, 1.0));
              },
      );
      await _writeExportDebugSnapshot(
        debugPath: debugPath,
        phase: 'after_run_from_frames',
        project: project,
        preset: preset,
        command: ffmpegCommand,
        args: args,
        outputPath: outputPath,
        timelineOriginMs: 0,
        outputDurationMs: durationMs,
        videoFilter: '<assembled_from_preview_frames>',
        audioFilter: '<none>',
        result: result,
      );

      if (result.exitCode != 0) {
        final String shortError = _compactError(
          (result.stderr ?? '').toString(),
        );
        throw Exception('Export FFmpeg echoue: $shortError');
      }
      onProgress?.call(1.0);
    } finally {
      if (frameDir.existsSync()) {
        try {
          frameDir.deleteSync(recursive: true);
        } on Object {
          // No-op: cleanup failure should not hide export result.
        }
      }
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

  Future<_HardwareProfile> _scanHardwareProfile() async {
    final int cpuCount = Platform.numberOfProcessors;
    double memoryGb = 8;
    bool onBattery = false;
    try {
      final ProcessResult memResult = await Process.run('sysctl', <String>[
        '-n',
        'hw.memsize',
      ]);
      final int? memBytes = int.tryParse(
        (memResult.stdout ?? '').toString().trim(),
      );
      if (memBytes != null && memBytes > 0) {
        memoryGb = memBytes / (1024 * 1024 * 1024);
      }
    } on Object {
      // Best effort only.
    }
    try {
      final ProcessResult battResult = await Process.run('pmset', <String>[
        '-g',
        'batt',
      ]);
      final String lower = '${battResult.stdout ?? ''}'.toLowerCase();
      onBattery = lower.contains('battery power');
    } on Object {
      // Best effort only.
    }
    if (onBattery || memoryGb < 8 || cpuCount <= 4) {
      return _HardwareProfile(
        mode: 'safe',
        cpuCount: cpuCount,
        memoryGb: memoryGb,
        interFrameDelayMs: 18,
      );
    }
    if (memoryGb < 16 || cpuCount <= 8) {
      return _HardwareProfile(
        mode: 'balanced',
        cpuCount: cpuCount,
        memoryGb: memoryGb,
        interFrameDelayMs: 8,
      );
    }
    return _HardwareProfile(
      mode: 'performance',
      cpuCount: cpuCount,
      memoryGb: memoryGb,
      interFrameDelayMs: 3,
    );
  }

  Future<void> _appendDebugNote(String debugPath, String note) async {
    try {
      await File(debugPath).writeAsString('$note\n', mode: FileMode.append);
    } on Object {
      // Best effort only.
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

  String _debugFilePath(String outputPath) {
    return '$outputPath.export-debug.txt';
  }

  Future<void> _writeExportDebugSnapshot({
    required String debugPath,
    required String phase,
    required Project project,
    required ExportPreset preset,
    required String command,
    required List<String> args,
    required String outputPath,
    required int timelineOriginMs,
    required int outputDurationMs,
    required String videoFilter,
    required String? audioFilter,
    ProcessResult? result,
    Object? launchError,
  }) async {
    try {
      final bool append = phase != 'before_run';
      final StringBuffer buffer = StringBuffer();
      if (!append) {
        buffer.writeln('PocketSunoMaker export debug');
        buffer.writeln('created_at=${DateTime.now().toIso8601String()}');
        buffer.writeln();
      }
      buffer.writeln('phase=$phase');
      buffer.writeln('output_path=$outputPath');
      buffer.writeln('debug_path=$debugPath');
      buffer.writeln(
        'preset=${preset.label} (${preset.width}x${preset.height}@${preset.frameRate}fps)',
      );
      buffer.writeln(
        'project_duration_ms=${project.durationMs}, output_duration_ms=$outputDurationMs',
      );
      buffer.writeln('timeline_origin_ms=$timelineOriginMs');
      buffer.writeln(
        'output_duration_sec=${(outputDurationMs / 1000).toStringAsFixed(3)}',
      );
      buffer.writeln();
      buffer.writeln('preview_timeline_snapshot=');
      for (final String line in _describePreviewTimelineSnapshot(
        project: project,
        timelineOriginMs: timelineOriginMs,
      )) {
        buffer.writeln(line);
      }
      buffer.writeln();
      buffer.writeln('visual_effect_clips=');
      for (final String line in _describeVisualEffectClips(
        project,
        timelineOriginMs,
      )) {
        buffer.writeln(line);
      }
      buffer.writeln();
      buffer.writeln('diff_preview_vs_export=');
      for (final String line in _describePreviewVsExportDiff(
        project: project,
        timelineOriginMs: timelineOriginMs,
        outputDurationMs: outputDurationMs,
      )) {
        buffer.writeln(line);
      }
      buffer.writeln();
      buffer.writeln('audio_effect_clips=');
      for (final String line in _describeAudioEffectClips(project)) {
        buffer.writeln(line);
      }
      buffer.writeln();
      buffer.writeln('video_filter=');
      buffer.writeln(videoFilter);
      buffer.writeln();
      buffer.writeln('audio_filter=');
      buffer.writeln(audioFilter ?? '<none>');
      buffer.writeln();
      buffer.writeln('ffmpeg_command=');
      buffer.writeln(command);
      buffer.writeln('ffmpeg_args=');
      buffer.writeln(args.map(_shellQuoteArg).join(' '));
      if (launchError != null) {
        buffer.writeln();
        buffer.writeln('launch_error=$launchError');
      }
      if (result != null) {
        buffer.writeln();
        buffer.writeln('exit_code=${result.exitCode}');
        buffer.writeln('stdout_tail=');
        buffer.writeln(_tailLines((result.stdout ?? '').toString(), 80));
        buffer.writeln();
        buffer.writeln('stderr_tail=');
        buffer.writeln(_tailLines((result.stderr ?? '').toString(), 80));
      }
      buffer.writeln('---');
      await File(debugPath).writeAsString(
        buffer.toString(),
        mode: append ? FileMode.append : FileMode.write,
      );
    } on Object {
      // Debug output must never fail the export path.
    }
  }

  List<String> _describeVisualEffectClips(
    Project project,
    int timelineOriginMs,
  ) {
    final List<Clip> clips =
        project.tracks
            .where((Track track) => track.type == TrackType.visualEffect)
            .expand((Track track) => track.clips)
            .where((Clip clip) => clip.visualEffectType != null)
            .toList(growable: false)
          ..sort(
            (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
          );
    if (clips.isEmpty) {
      return const <String>['<none>'];
    }
    return clips
        .map((Clip clip) {
          final int startRelMs = clip.timelineStartMs - timelineOriginMs;
          final int endRelMs = startRelMs + clip.durationMs;
          return '- id=${clip.id} type=${clip.visualEffectType?.name} '
              'timeline=[${clip.timelineStartMs}-${clip.timelineStartMs + clip.durationMs}] '
              'relative=[$startRelMs-$endRelMs] '
              'duration_ms=${clip.durationMs} intensity=${clip.effectIntensity.toStringAsFixed(3)}';
        })
        .toList(growable: false);
  }

  List<String> _describePreviewTimelineSnapshot({
    required Project project,
    required int timelineOriginMs,
  }) {
    final List<String> lines = <String>[];
    lines.add(
      '- project_duration_ms=${project.durationMs} timeline_origin_ms=$timelineOriginMs',
    );
    lines.addAll(
      _describeTrackClipsForPreview(
        project: project,
        type: TrackType.video,
        label: 'video',
        timelineOriginMs: timelineOriginMs,
      ),
    );
    lines.addAll(
      _describeTrackClipsForPreview(
        project: project,
        type: TrackType.audio,
        label: 'audio',
        timelineOriginMs: timelineOriginMs,
      ),
    );
    lines.addAll(
      _describeTrackClipsForPreview(
        project: project,
        type: TrackType.text,
        label: 'text',
        timelineOriginMs: timelineOriginMs,
      ),
    );
    lines.addAll(
      _describeTrackClipsForPreview(
        project: project,
        type: TrackType.visualEffect,
        label: 'visual_effect',
        timelineOriginMs: timelineOriginMs,
      ),
    );
    lines.addAll(
      _describeTrackClipsForPreview(
        project: project,
        type: TrackType.audioEffect,
        label: 'audio_effect',
        timelineOriginMs: timelineOriginMs,
      ),
    );
    return lines;
  }

  List<String> _describeTrackClipsForPreview({
    required Project project,
    required TrackType type,
    required String label,
    required int timelineOriginMs,
  }) {
    final List<Clip> clips =
        project.tracks
            .where((Track track) => track.type == type)
            .expand((Track track) => track.clips)
            .toList(growable: false)
          ..sort(
            (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
          );
    if (clips.isEmpty) {
      return <String>['- $label: <none>'];
    }
    final List<String> lines = <String>['- $label: count=${clips.length}'];
    for (final Clip clip in clips) {
      final int startMs = clip.timelineStartMs;
      final int endMs = clip.timelineStartMs + clip.durationMs;
      final int relStartMs = startMs - timelineOriginMs;
      final int relEndMs = relStartMs + clip.durationMs;
      final String effectType =
          clip.visualEffectType?.name ?? clip.audioEffectType?.name ?? '-';
      lines.add(
        '  - id=${clip.id} kind=$effectType timeline=[$startMs-$endMs] '
        'relative=[$relStartMs-$relEndMs] duration_ms=${clip.durationMs}',
      );
    }
    return lines;
  }

  List<String> _describePreviewVsExportDiff({
    required Project project,
    required int timelineOriginMs,
    required int outputDurationMs,
  }) {
    final List<Clip> visualClips =
        project.tracks
            .where((Track track) => track.type == TrackType.visualEffect)
            .expand((Track track) => track.clips)
            .where((Clip clip) => clip.visualEffectType != null)
            .toList(growable: false)
          ..sort(
            (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
          );
    if (visualClips.isEmpty) {
      return const <String>['- visual_effects: <none>'];
    }
    final double outputSec = outputDurationMs <= 0
        ? 0
        : outputDurationMs / 1000.0;
    final List<String> lines = <String>[
      '- output_window_sec=[0.000-${outputSec.toStringAsFixed(3)}]',
    ];
    for (final Clip clip in visualClips) {
      final double previewStart =
          (clip.timelineStartMs - timelineOriginMs) / 1000;
      final double previewEnd = previewStart + (clip.durationMs / 1000.0);
      final double exportStart = previewStart.clamp(0.0, outputSec);
      final double exportEnd = previewEnd.clamp(0.0, outputSec);
      final bool applies = outputSec > 0 && exportEnd > exportStart;
      final String status = applies ? 'OK_APPLIED' : 'MISMATCH_OUT_OF_RANGE';
      lines.add(
        '- id=${clip.id} type=${clip.visualEffectType?.name} status=$status '
        'preview_sec=[${previewStart.toStringAsFixed(3)}-${previewEnd.toStringAsFixed(3)}] '
        'export_sec=[${exportStart.toStringAsFixed(3)}-${exportEnd.toStringAsFixed(3)}]',
      );
    }
    return lines;
  }

  List<String> _describeAudioEffectClips(Project project) {
    final List<Clip> clips =
        project.tracks
            .where((Track track) => track.type == TrackType.audioEffect)
            .expand((Track track) => track.clips)
            .where((Clip clip) => clip.audioEffectType != null)
            .toList(growable: false)
          ..sort(
            (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
          );
    if (clips.isEmpty) {
      return const <String>['<none>'];
    }
    return clips
        .map((Clip clip) {
          return '- id=${clip.id} type=${clip.audioEffectType?.name} '
              'timeline=[${clip.timelineStartMs}-${clip.timelineStartMs + clip.durationMs}] '
              'duration_ms=${clip.durationMs} intensity=${clip.effectIntensity.toStringAsFixed(3)}';
        })
        .toList(growable: false);
  }

  String _shellQuoteArg(String arg) {
    if (arg.isEmpty) {
      return "''";
    }
    final bool needsQuote =
        arg.contains(' ') ||
        arg.contains('"') ||
        arg.contains("'") ||
        arg.contains(r'$') ||
        arg.contains('`') ||
        arg.contains(r'\');
    if (!needsQuote) {
      return arg;
    }
    return "'${arg.replaceAll("'", "'\"'\"'")}'";
  }

  String _tailLines(String value, int maxLines) {
    final List<String> lines = value
        .split('\n')
        .where((String line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return '<empty>';
    }
    final int start = math.max(0, lines.length - maxLines);
    return lines.sublist(start).join('\n');
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
    int? stillImageFrameRate,
  }) {
    args.addAll(<String>['-ss', (clip.sourceInMs / 1000).toStringAsFixed(3)]);
    args.addAll(<String>['-t', (clip.durationMs / 1000).toStringAsFixed(3)]);
    if (loopStillImage) {
      final int safeFrameRate = (stillImageFrameRate ?? 30).clamp(1, 120);
      args.addAll(<String>['-framerate', safeFrameRate.toString()]);
      args.addAll(<String>['-loop', '1']);
    }
    args.addAll(<String>['-i', clip.assetPath]);
  }

  String _buildVideoFilter({
    required Project project,
    required ExportPreset preset,
    required bool includeVisualEffects,
    required int timelineOriginMs,
    required bool sourceIsStillImage,
    required int outputDurationMs,
  }) {
    final String baseScale =
        'scale=${preset.width}:${preset.height}:force_original_aspect_ratio=decrease';
    final String finalPad =
        'pad=${preset.width}:${preset.height}:(ow-iw)/2:(oh-ih)/2';
    final List<String> filters = <String>[
      if (sourceIsStillImage)
        // For looped still images, force a real frame timeline so FFmpeg's
        // t/enable expressions used by visual effects evolve over time.
        'fps=${preset.frameRate},setpts=N/(FRAME_RATE*TB)',
      // Keep visual effects on the media surface before padding to better
      // match preview behavior (where effects are applied on the visual layer).
      baseScale,
    ];
    final List<Clip> visualEffectClips =
        project.tracks
            .where((Track track) => track.type == TrackType.visualEffect)
            .expand((Track track) => track.clips)
            .where((Clip clip) => clip.visualEffectType != null)
            .toList(growable: false)
          ..sort(
            (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
          );
    final List<Clip> textClips =
        project.tracks
            .where((Track track) => track.type == TrackType.text)
            .expand((Track track) => track.clips)
            .toList(growable: false)
          ..sort(
            (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
          );
    if (includeVisualEffects && visualEffectClips.isNotEmpty) {
      int addedCount = 0;
      for (final Clip effectClip in visualEffectClips) {
        final List<String> built = _buildVisualEffectFilters(
          effectClip,
          timelineOriginMs: timelineOriginMs,
          outputDurationMs: outputDurationMs,
        );
        addedCount += built.length;
        filters.addAll(built);
      }
      // Fallback: if timing math clipped every effect out, force-apply effects
      // to avoid silent "no effect in export" regressions.
      if (addedCount == 0) {
        for (final Clip effectClip in visualEffectClips) {
          filters.addAll(
            _buildVisualEffectFilters(
              effectClip,
              timelineOriginMs: timelineOriginMs,
              outputDurationMs: outputDurationMs,
              forceAlwaysOn: true,
            ),
          );
        }
      }
    }
    // Pad to final canvas after visual effects, before optional drawtext.
    filters.add(finalPad);
    if (textClips.isEmpty) {
      return filters.join(',');
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
      final double start = (clip.timelineStartMs - timelineOriginMs) / 1000;
      final double end =
          (clip.timelineStartMs + clip.durationMs - timelineOriginMs) / 1000;
      if (end <= 0) {
        continue;
      }
      final double safeStart = start < 0 ? 0 : start;
      final double safeEnd = end < safeStart ? safeStart : end;
      final String fontColor = clip.textColorHex.replaceAll('#', '');
      final String boxColor = clip.textBackgroundHex.replaceAll('#', '');
      final double textOpacity = clip.opacity.clamp(0.0, 1.0);
      final String boxOpacityStr = (textOpacity * 0.62).toStringAsFixed(3);
      final String alphaExpr = _buildTextAlphaExpression(
        clip: clip,
        start: safeStart,
        end: safeEnd,
        baseOpacity: textOpacity,
      );
      final String yExpr = _buildTextYExpression(
        clip: clip,
        start: safeStart,
        end: safeEnd,
        baseYOffset: yOffset,
      );
      final String fontSizeExpr = _buildTextFontSizeExpression(
        clip: clip,
        start: safeStart,
        end: safeEnd,
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
        "enable='between(t\\,${safeStart.toStringAsFixed(3)}\\,${safeEnd.toStringAsFixed(3)})'",
      );
      if (clip.karaokeEnabled) {
        final String karaokeColor = clip.karaokeFillColorHex.replaceAll(
          '#',
          '',
        );
        final String karaokeProgressExpr = _buildKaraokeProgressExpression(
          clip: clip,
          start: safeStart,
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
          "enable='between(t\\,${safeStart.toStringAsFixed(3)}\\,${safeEnd.toStringAsFixed(3)})'",
        );
      }
    }
    if (drawTextFilters.isEmpty) {
      return filters.join(',');
    }
    return <String>[...filters, ...drawTextFilters].join(',');
  }

  List<String> _buildVisualEffectFilters(
    Clip clip, {
    required int timelineOriginMs,
    required int outputDurationMs,
    bool forceAlwaysOn = false,
  }) {
    final VisualEffectType? type = clip.visualEffectType;
    if (type == null) {
      return const <String>[];
    }
    final double start = forceAlwaysOn
        ? 0
        : (clip.timelineStartMs - timelineOriginMs) / 1000;
    final double end = forceAlwaysOn
        ? 1e9
        : (clip.timelineStartMs + clip.durationMs - timelineOriginMs) / 1000;
    if (end <= 0) {
      return const <String>[];
    }
    final double safeStart = start < 0 ? 0 : start;
    final double safeEnd = end < safeStart ? safeStart : end;
    final double outputDurationSec = outputDurationMs <= 0
        ? 1e9
        : outputDurationMs / 1000.0;
    if (!forceAlwaysOn &&
        (safeEnd <= 0 ||
            safeStart >= outputDurationSec ||
            outputDurationSec <= 0)) {
      return const <String>[];
    }
    final double boundedStart = forceAlwaysOn
        ? safeStart
        : safeStart.clamp(0.0, outputDurationSec);
    final double boundedEnd = forceAlwaysOn
        ? safeEnd
        : safeEnd.clamp(0.0, outputDurationSec);
    if (!forceAlwaysOn && boundedEnd <= boundedStart) {
      return const <String>[];
    }
    final double intensity = clip.effectIntensity.clamp(0.1, 1.0);
    final String enabled = _enableBetween(boundedStart, boundedEnd);
    switch (type) {
      case VisualEffectType.glitch:
        final double tearStrength = clip.effectGlitchTearStrength.clamp(
          0.05,
          1.0,
        );
        final double noiseAmount = clip.effectGlitchNoiseAmount.clamp(0.0, 1.0);
        final bool audioSync = clip.effectGlitchAudioSync;
        final double lineMix = clip.effectGlitchLineMix.clamp(0.0, 1.0);
        final double blockMix = clip.effectGlitchBlockMix.clamp(0.0, 1.0);
        final double blockSize = clip.effectGlitchBlockSizePx.clamp(6.0, 90.0);
        final String phaseExpr = audioSync
            ? 't'
            : '(t-${boundedStart.toStringAsFixed(3)})';
        final String activeExpr = _betweenExpr(boundedStart, boundedEnd);
        final int noiseStrength = (14 + intensity * 32 + noiseAmount * 26)
            .round()
            .clamp(0, 100);
        int cropPx = (12 + intensity * 24 + tearStrength * 26).round();
        if (cropPx.isOdd) {
          cropPx += 1;
        }
        final double amp = 6.0 + intensity * 20 + tearStrength * 14;
        final int boxH = (4 + (1 + intensity * 12) * (0.55 + lineMix * 1.10))
            .round();
        final double boxAlpha = (0.22 + (0.20 + lineMix * 0.28) * intensity)
            .clamp(0.0, 1.0);
        final int blockW = (blockSize * (1.20 + blockMix * 2.2)).round();
        final int blockH = (blockSize * (0.60 + blockMix * 1.2)).round();
        final double blockAlpha = (0.16 + (0.16 + blockMix * 0.24) * intensity)
            .clamp(0.0, 0.82);
        final String colorA = _sanitizeHexRgb(
          clip.effectGlitchColorAHex,
          fallback: '00E5FF',
        );
        final String colorB = _sanitizeHexRgb(
          clip.effectGlitchColorBHex,
          fallback: 'FF00E6',
        );
        return <String>[
          'noise=alls=$noiseStrength:allf=t+u:$enabled',
          "colorbalance="
              "rs=${(0.03 + intensity * 0.18).toStringAsFixed(3)}:"
              "bs=${(-0.03 - intensity * 0.18).toStringAsFixed(3)}:"
              "$enabled",
          "eq=contrast=${(1.02 + intensity * 0.16).toStringAsFixed(3)}:"
              "saturation=${(1.00 + intensity * 0.12).toStringAsFixed(3)}:"
              "brightness='${(-0.01 + intensity * 0.02).toStringAsFixed(3)}+${(0.012 + intensity * 0.030).toStringAsFixed(3)}*sin(14*$phaseExpr)':"
              "$enabled",
          "crop="
              "w='iw-if($activeExpr\\,$cropPx\\,0)':"
              "h='ih-if($activeExpr\\,$cropPx\\,0)':"
              "x='if($activeExpr\\,clip(${(cropPx / 2).toStringAsFixed(2)}+${amp.toStringAsFixed(2)}*sin(63*$phaseExpr)\\,0\\,iw-ow)\\,0)':"
              "y='if($activeExpr\\,clip(${(cropPx / 2).toStringAsFixed(2)}+${(amp * 0.7).toStringAsFixed(2)}*cos(41*$phaseExpr)\\,0\\,ih-oh)\\,0)'",
          'scale=iw:ih',
          "drawbox=x=0:y='mod(t*240\\,ih)':w=iw:h=$boxH:"
              'color=0x$colorA@${boxAlpha.toStringAsFixed(3)}:t=fill:$enabled',
          "drawbox=x=0:y='mod(t*170+123\\,ih)':w=iw:h=$boxH:"
              'color=0x$colorB@${(boxAlpha * 0.85).toStringAsFixed(3)}:t=fill:$enabled',
          "drawbox=x='mod($phaseExpr*97\\,iw)':y='mod($phaseExpr*61\\,ih)':"
              "w=$blockW:h=$blockH:"
              'color=0x$colorA@${blockAlpha.toStringAsFixed(3)}:t=fill:$enabled',
          "drawbox=x='mod($phaseExpr*71+120\\,iw)':y='mod($phaseExpr*83+44\\,ih)':"
              "w=${(blockW * 0.72).round()}:h=${(blockH * 0.72).round()}:"
              'color=0x$colorB@${(blockAlpha * 0.9).toStringAsFixed(3)}:t=fill:$enabled',
        ];
      case VisualEffectType.shake:
        final double start = boundedStart;
        final double baseAmplitude = clip.effectShakeAmplitudePx.clamp(
          2.0,
          40.0,
        );
        final double amplitude = baseAmplitude * (1.10 + intensity * 1.50);
        final double frequencyHz = clip.effectShakeAutoBpm
            ? (clip.effectShakeDetectedBpm.clamp(60.0, 220.0) / 60.0)
            : clip.effectShakeFrequencyHz.clamp(4.0, 60.0);
        final String phaseExpr = clip.effectShakeAudioSync
            ? 't'
            : '(t-${start.toStringAsFixed(3)})';
        final String activeExpr = _betweenExpr(boundedStart, boundedEnd);
        int cropPx = (14 + amplitude * 2.6).round().clamp(14, 140);
        if (cropPx.isOdd) {
          cropPx += 1;
        }
        final double shakeX = amplitude;
        final double shakeY = amplitude * 0.68;
        final String wx = (math.pi * 2 * frequencyHz).toStringAsFixed(3);
        final String wy = (math.pi * 2 * (frequencyHz * 0.77)).toStringAsFixed(
          3,
        );
        return <String>[
          "crop="
              "w='iw-if($activeExpr\\,$cropPx\\,0)':"
              "h='ih-if($activeExpr\\,$cropPx\\,0)':"
              "x='if($activeExpr\\,clip(${(cropPx / 2).toStringAsFixed(2)}+${shakeX.toStringAsFixed(2)}*sin($wx*$phaseExpr)\\,0\\,iw-ow)\\,0)':"
              "y='if($activeExpr\\,clip(${(cropPx / 2).toStringAsFixed(2)}+${shakeY.toStringAsFixed(2)}*cos($wy*$phaseExpr)\\,0\\,ih-oh)\\,0)'",
          'scale=iw:ih',
        ];
      case VisualEffectType.rgbSplit:
        return <String>[
          "colorbalance="
              "rs=${(0.04 + intensity * 0.20).toStringAsFixed(3)}:"
              "bs=${(-0.04 - intensity * 0.20).toStringAsFixed(3)}:"
              "$enabled",
          "eq=saturation=${(1.08 + intensity * 0.26).toStringAsFixed(3)}:$enabled",
        ];
      case VisualEffectType.flash:
        final double brightnessBase = 0.03 + intensity * 0.05;
        final double pulse = 0.10 + intensity * 0.22;
        return <String>[
          "eq=brightness='${brightnessBase.toStringAsFixed(3)}+${pulse.toStringAsFixed(3)}*abs(sin(14*t))':"
              "saturation=${(1.0 + intensity * 0.2).toStringAsFixed(3)}:"
              "$enabled",
        ];
      case VisualEffectType.vhs:
        final int noiseStrength = (4 + intensity * 16).round();
        final int scanlineH = (1 + intensity * 3).round();
        final double scanAlpha = (0.08 + intensity * 0.16).clamp(0.0, 1.0);
        return <String>[
          "eq=contrast=${(0.96 + intensity * 0.10).toStringAsFixed(3)}:"
              "saturation=${(0.76 + intensity * 0.16).toStringAsFixed(3)}:"
              "brightness=${(-0.03).toStringAsFixed(3)}:$enabled",
          'noise=alls=$noiseStrength:allf=t:$enabled',
          "drawbox=x=0:y='mod(t*120\\,ih)':w=iw:h=$scanlineH:"
              'color=black@${scanAlpha.toStringAsFixed(3)}:t=fill:$enabled',
        ];
    }
  }

  String _enableBetween(double startSec, double endSec) {
    return "enable='between(t\\,${startSec.toStringAsFixed(3)}\\,${endSec.toStringAsFixed(3)})'";
  }

  String _betweenExpr(double startSec, double endSec) {
    return 'between(t\\,${startSec.toStringAsFixed(3)}\\,${endSec.toStringAsFixed(3)})';
  }

  String? _buildAudioFilter({
    required Project project,
    required int timelineOriginMs,
  }) {
    final List<Clip> audioEffects =
        project.tracks
            .where((Track track) => track.type == TrackType.audioEffect)
            .expand((Track track) => track.clips)
            .where((Clip clip) => clip.audioEffectType != null)
            .toList(growable: false)
          ..sort(
            (Clip a, Clip b) => a.timelineStartMs.compareTo(b.timelineStartMs),
          );
    if (audioEffects.isEmpty) {
      return null;
    }

    final List<String> filters = <String>[];
    for (final Clip effect in audioEffects) {
      final AudioEffectType? type = effect.audioEffectType;
      if (type == null) {
        continue;
      }
      final double start = (effect.timelineStartMs - timelineOriginMs) / 1000;
      final double end =
          (effect.timelineStartMs + effect.durationMs - timelineOriginMs) /
          1000;
      if (end <= 0) {
        continue;
      }
      final double safeStart = start < 0 ? 0 : start;
      final double safeEnd = end < safeStart ? safeStart : end;
      final String enabled = _enableBetween(safeStart, safeEnd);
      final double intensity = effect.effectIntensity.clamp(0.1, 1.0);
      switch (type) {
        case AudioEffectType.censorBeep:
          // V1 export: mute segment (preview superposes generated beep).
          filters.add('volume=0:$enabled');
          break;
        case AudioEffectType.distortion:
          final int highpassHz = (90 + intensity * 220).round();
          final int lowpassHz = (3200 + intensity * 1800).round();
          final double gain = 1.10 + intensity * 0.85;
          filters.add('highpass=f=$highpassHz:$enabled');
          filters.add('lowpass=f=$lowpassHz:$enabled');
          filters.add('volume=${gain.toStringAsFixed(3)}:$enabled');
          break;
        case AudioEffectType.stutter:
          final double period = (0.18 - intensity * 0.11).clamp(0.05, 0.18);
          final double gateOn = (0.028 + intensity * 0.028).clamp(0.018, 0.08);
          final String startS = safeStart.toStringAsFixed(3);
          final String periodS = period.toStringAsFixed(3);
          final String gateOnS = gateOn.toStringAsFixed(3);
          filters.add(
            "volume='if(between(t\\,$startS\\,${safeEnd.toStringAsFixed(3)})\\,"
            "if(lt(mod(t-$startS\\,$periodS)\\,$gateOnS)\\,1\\,0)\\,1)'",
          );
          break;
      }
    }
    if (filters.isEmpty) {
      return null;
    }
    return filters.join(',');
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

  String _sanitizeHexRgb(String hex, {required String fallback}) {
    final String normalized = hex.replaceAll('#', '').trim();
    if (normalized.length != 6) {
      return fallback;
    }
    final int? value = int.tryParse(normalized, radix: 16);
    if (value == null) {
      return fallback;
    }
    return normalized.toUpperCase();
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

class _HardwareProfile {
  const _HardwareProfile({
    required this.mode,
    required this.cpuCount,
    required this.memoryGb,
    required this.interFrameDelayMs,
  });

  final String mode;
  final int cpuCount;
  final double memoryGb;
  final int interFrameDelayMs;
}
