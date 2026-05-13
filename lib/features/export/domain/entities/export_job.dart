enum ExportJobStatus { queued, running, succeeded, failed, canceled }

class ExportJob {
  const ExportJob({
    required this.id,
    required this.presetLabel,
    required this.outputPath,
    required this.status,
    this.message,
    this.progress,
    this.startedAtEpochMs,
  });

  final String id;
  final String presetLabel;
  final String outputPath;
  final ExportJobStatus status;
  final String? message;
  final double? progress;
  final int? startedAtEpochMs;

  ExportJob copyWith({
    String? id,
    String? presetLabel,
    String? outputPath,
    ExportJobStatus? status,
    String? message,
    double? progress,
    int? startedAtEpochMs,
  }) {
    return ExportJob(
      id: id ?? this.id,
      presetLabel: presetLabel ?? this.presetLabel,
      outputPath: outputPath ?? this.outputPath,
      status: status ?? this.status,
      message: message,
      progress: progress ?? this.progress,
      startedAtEpochMs: startedAtEpochMs ?? this.startedAtEpochMs,
    );
  }
}
