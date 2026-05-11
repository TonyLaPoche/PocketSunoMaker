import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../project/domain/entities/export_preset.dart';
import '../../../project/domain/entities/project.dart';
import '../../domain/entities/export_job.dart';
import '../../infrastructure/services/ffmpeg_export_service.dart';
import 'export_queue_state.dart';

final Provider<FfmpegExportService> ffmpegExportServiceProvider =
    Provider<FfmpegExportService>((Ref ref) {
      return const FfmpegExportService();
    });

final NotifierProvider<ExportQueueController, ExportQueueState>
exportQueueControllerProvider =
    NotifierProvider<ExportQueueController, ExportQueueState>(
      ExportQueueController.new,
    );

class ExportQueueController extends Notifier<ExportQueueState> {
  late final FfmpegExportService _ffmpegExportService;
  final List<_QueuedExportRequest> _requests = <_QueuedExportRequest>[];

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

  Future<void> enqueueExport(Project? project) async {
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
    );

    _requests.add(
      _QueuedExportRequest(
        id: jobId,
        project: project,
        preset: preset,
        outputPath: destination.path,
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
    _updateJobStatus(request.id, ExportJobStatus.running);

    try {
      await _ffmpegExportService.exportProject(
        project: request.project,
        preset: request.preset,
        outputPath: request.outputPath,
      );
      _updateJobStatus(
        request.id,
        ExportJobStatus.succeeded,
        message: 'Export termine.',
      );
    } catch (error) {
      _updateJobStatus(
        request.id,
        ExportJobStatus.failed,
        message: error.toString(),
      );
      state = state.copyWith(
        errorMessage: 'Export echoue: ${request.preset.label}',
      );
    }

    if (_requests.isEmpty) {
      state = state.copyWith(isProcessing: false);
      return;
    }
    await _processQueue();
  }

  void _updateJobStatus(
    String jobId,
    ExportJobStatus status, {
    String? message,
  }) {
    final List<ExportJob> updated = state.jobs
        .map((ExportJob job) {
          if (job.id != jobId) {
            return job;
          }
          return job.copyWith(status: status, message: message);
        })
        .toList(growable: false);

    state = state.copyWith(jobs: updated);
  }
}

class _QueuedExportRequest {
  const _QueuedExportRequest({
    required this.id,
    required this.project,
    required this.preset,
    required this.outputPath,
  });

  final String id;
  final Project project;
  final ExportPreset preset;
  final String outputPath;
}
