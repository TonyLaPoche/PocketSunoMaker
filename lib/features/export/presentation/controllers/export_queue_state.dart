import '../../../project/domain/entities/export_preset.dart';
import '../../domain/entities/export_job.dart';

class ExportQueueState {
  ExportQueueState({
    this.jobs = const <ExportJob>[],
    ExportPreset? selectedPreset,
    this.isProcessing = false,
    this.errorMessage,
  }) : selectedPreset = selectedPreset ?? ExportPreset.defaults.first;

  final List<ExportJob> jobs;
  final ExportPreset selectedPreset;
  final bool isProcessing;
  final String? errorMessage;

  ExportQueueState copyWith({
    List<ExportJob>? jobs,
    ExportPreset? selectedPreset,
    bool? isProcessing,
    String? errorMessage,
  }) {
    return ExportQueueState(
      jobs: jobs ?? this.jobs,
      selectedPreset: selectedPreset ?? this.selectedPreset,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: errorMessage,
    );
  }
}
