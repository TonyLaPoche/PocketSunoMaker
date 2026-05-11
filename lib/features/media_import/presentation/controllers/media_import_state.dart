import '../../domain/entities/media_asset.dart';

class MediaImportState {
  const MediaImportState({
    this.assets = const <MediaAsset>[],
    this.isLoading = false,
    this.errorMessage,
    this.isDraggingOver = false,
  });

  final List<MediaAsset> assets;
  final bool isLoading;
  final String? errorMessage;
  final bool isDraggingOver;

  MediaImportState copyWith({
    List<MediaAsset>? assets,
    bool? isLoading,
    String? errorMessage,
    bool? isDraggingOver,
  }) {
    return MediaImportState(
      assets: assets ?? this.assets,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isDraggingOver: isDraggingOver ?? this.isDraggingOver,
    );
  }
}
