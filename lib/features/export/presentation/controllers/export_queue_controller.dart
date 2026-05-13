import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../../../project/domain/entities/export_preset.dart';
import '../../../project/domain/entities/project.dart';
import '../../domain/entities/export_job.dart';
import '../../infrastructure/services/ffmpeg_export_service.dart';
import 'export_queue_state.dart';

final Provider<FfmpegExportService> ffmpegExportServiceProvider =
    Provider<FfmpegExportService>((Ref ref) {
      return FfmpegExportService();
    });

final NotifierProvider<ExportQueueController, ExportQueueState>
exportQueueControllerProvider =
    NotifierProvider<ExportQueueController, ExportQueueState>(
      ExportQueueController.new,
    );

class ExportQueueController extends Notifier<ExportQueueState> {
  late final FfmpegExportService _ffmpegExportService;
  final List<_QueuedExportRequest> _requests = <_QueuedExportRequest>[];
  String? _runningJobId;

  static const XTypeGroup _outputTypeGroup = XTypeGroup(
    label: 'MP4 Video',
    extensions: <String>['mp4'],
  );

  @override
  ExportQueueState build() {
    _ffmpegExportService = ref.read(ffmpegExportServiceProvider);
    return ExportQueueState(selectedPreset: ExportPreset.defaults.first);
  }

  void selectPreset(ExportPreset preset) {
    state = state.copyWith(selectedPreset: preset, errorMessage: null);
  }

  Future<void> enqueueExport(
    Project? project, {
    Future<Uint8List?> Function(int positionMs)? renderFramePngAt,
  }) async {
    if (project == null) {
      state = state.copyWith(errorMessage: 'Cree un projet avant d exporter.');
      return;
    }

    final ExportPreset preset = state.selectedPreset;
    final FileSaveLocation? destination = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[_outputTypeGroup],
      suggestedName: 'PocketSunoMaker_${preset.label.replaceAll(' ', '_')}.mp4',
    );
    if (destination == null) {
      return;
    }

    final String jobId = 'export-${DateTime.now().microsecondsSinceEpoch}';
    final ExportJob queuedJob = ExportJob(
      id: jobId,
      presetLabel: preset.label,
      outputPath: destination.path,
      status: ExportJobStatus.queued,
      progress: 0,
      startedAtEpochMs: null,
    );

    _requests.add(
      _QueuedExportRequest(
        id: jobId,
        project: project,
        preset: preset,
        outputPath: destination.path,
        renderFramePngAt: renderFramePngAt,
      ),
    );

    state = state.copyWith(
      jobs: <ExportJob>[queuedJob, ...state.jobs],
      errorMessage: null,
    );

    if (!state.isProcessing) {
      await _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_requests.isEmpty) {
      state = state.copyWith(isProcessing: false);
      return;
    }

    state = state.copyWith(isProcessing: true);
    final _QueuedExportRequest request = _requests.removeAt(0);
    _runningJobId = request.id;
    _updateJobStatus(
      request.id,
      ExportJobStatus.running,
      progress: 0,
      startedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      if (request.renderFramePngAt != null) {
        await _ffmpegExportService.exportProjectFromPreviewFrames(
          project: request.project,
          preset: request.preset,
          outputPath: request.outputPath,
          renderFramePngAt: request.renderFramePngAt!,
          onProgress: (double progress) {
            _updateJobProgress(request.id, progress);
          },
        );
      } else {
        await _ffmpegExportService.exportProject(
          project: request.project,
          preset: request.preset,
          outputPath: request.outputPath,
          onProgress: (double progress) {
            _updateJobProgress(request.id, progress);
          },
        );
      }
      _updateJobStatus(
        request.id,
        ExportJobStatus.succeeded,
        message:
            'Export termine. Debug: ${request.outputPath}.export-debug.txt',
        progress: 1,
      );
    } catch (error) {
      final String details = _humanizeError(error);
      if (_isCancellation(details)) {
        _updateJobStatus(
          request.id,
          ExportJobStatus.canceled,
          message: 'Export annule par utilisateur.',
          progress: null,
        );
      } else {
        _updateJobStatus(
          request.id,
          ExportJobStatus.failed,
          message: details,
          progress: null,
        );
        state = state.copyWith(
          errorMessage: 'Export echoue (${request.preset.label}): $details',
        );
      }
    }
    _runningJobId = null;

    if (_requests.isEmpty) {
      state = state.copyWith(isProcessing: false);
      return;
    }
    await _processQueue();
  }

  void cancelRunningExport() {
    final String? runningJobId = _runningJobId;
    if (runningJobId == null) {
      return;
    }
    _ffmpegExportService.cancelCurrentExport();
  }

  void _updateJobStatus(
    String jobId,
    ExportJobStatus status, {
    String? message,
    double? progress,
    int? startedAtEpochMs,
  }) {
    final List<ExportJob> updated = state.jobs
        .map((ExportJob job) {
          if (job.id != jobId) {
            return job;
          }
          return job.copyWith(
            status: status,
            message: message,
            progress: progress,
            startedAtEpochMs: startedAtEpochMs,
          );
        })
        .toList(growable: false);

    state = state.copyWith(jobs: updated);
  }

  void _updateJobProgress(String jobId, double progress) {
    final double normalized = progress.clamp(0.0, 1.0);
    final List<ExportJob> updated = state.jobs
        .map((ExportJob job) {
          if (job.id != jobId) {
            return job;
          }
          final double previous = job.progress ?? 0;
          if ((normalized - previous).abs() < 0.002) {
            return job;
          }
          return job.copyWith(progress: normalized);
        })
        .toList(growable: false);
    state = state.copyWith(jobs: updated);
  }

  String _humanizeError(Object error) {
    final String raw = error.toString().trim();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }

  bool _isCancellation(String message) {
    final String lower = message.toLowerCase();
    return lower.contains('annule') || lower.contains('canceled');
  }
}

class _QueuedExportRequest {
  const _QueuedExportRequest({
    required this.id,
    required this.project,
    required this.preset,
    required this.outputPath,
    this.renderFramePngAt,
  });

  final String id;
  final Project project;
  final ExportPreset preset;
  final String outputPath;
  final Future<Uint8List?> Function(int positionMs)? renderFramePngAt;
}
