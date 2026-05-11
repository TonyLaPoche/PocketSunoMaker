enum ExportJobStatus { queued, running, succeeded, failed }

class ExportJob {
  const ExportJob({
    required this.id,
    required this.presetLabel,
    required this.outputPath,
    required this.status,
    this.message,
  });

  final String id;
  final String presetLabel;
  final String outputPath;
  final ExportJobStatus status;
  final String? message;

  ExportJob copyWith({
    String? id,
    String? presetLabel,
    String? outputPath,
    ExportJobStatus? status,
    String? message,
  }) {
    return ExportJob(
      id: id ?? this.id,
      presetLabel: presetLabel ?? this.presetLabel,
      outputPath: outputPath ?? this.outputPath,
      status: status ?? this.status,
      message: message,
    );
  }
}
