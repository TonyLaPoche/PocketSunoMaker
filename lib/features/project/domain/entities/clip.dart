class Clip {
  const Clip({
    required this.id,
    required this.assetPath,
    required this.timelineStartMs,
    required this.sourceInMs,
    required this.sourceOutMs,
    this.opacity = 1.0,
    this.speed = 1.0,
    this.volume = 1.0,
    this.scale = 1.0,
    this.rotationDeg = 0.0,
    this.textContent,
    this.textPosXPx = 0.0,
    this.textPosYPx = 0.0,
    this.textFontSizePx = 42.0,
    this.textFontFamily = 'Roboto',
    this.textBold = false,
    this.textItalic = false,
    this.textColorHex = '#FFFFFF',
    this.textBackgroundHex = '#000000',
    this.textShowBackground = true,
    this.textShowBorder = true,
  });

  final String id;
  final String assetPath;
  final int timelineStartMs;
  final int sourceInMs;
  final int sourceOutMs;
  final double opacity;
  final double speed;
  final double volume;
  final double scale;
  final double rotationDeg;
  final String? textContent;
  final double textPosXPx;
  final double textPosYPx;
  final double textFontSizePx;
  final String textFontFamily;
  final bool textBold;
  final bool textItalic;
  final String textColorHex;
  final String textBackgroundHex;
  final bool textShowBackground;
  final bool textShowBorder;

  int get durationMs => sourceOutMs - sourceInMs;

  Clip copyWith({
    String? id,
    String? assetPath,
    int? timelineStartMs,
    int? sourceInMs,
    int? sourceOutMs,
    double? opacity,
    double? speed,
    double? volume,
    double? scale,
    double? rotationDeg,
    String? textContent,
    double? textPosXPx,
    double? textPosYPx,
    double? textFontSizePx,
    String? textFontFamily,
    bool? textBold,
    bool? textItalic,
    String? textColorHex,
    String? textBackgroundHex,
    bool? textShowBackground,
    bool? textShowBorder,
  }) {
    return Clip(
      id: id ?? this.id,
      assetPath: assetPath ?? this.assetPath,
      timelineStartMs: timelineStartMs ?? this.timelineStartMs,
      sourceInMs: sourceInMs ?? this.sourceInMs,
      sourceOutMs: sourceOutMs ?? this.sourceOutMs,
      opacity: opacity ?? this.opacity,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      scale: scale ?? this.scale,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      textContent: textContent ?? this.textContent,
      textPosXPx: textPosXPx ?? this.textPosXPx,
      textPosYPx: textPosYPx ?? this.textPosYPx,
      textFontSizePx: textFontSizePx ?? this.textFontSizePx,
      textFontFamily: textFontFamily ?? this.textFontFamily,
      textBold: textBold ?? this.textBold,
      textItalic: textItalic ?? this.textItalic,
      textColorHex: textColorHex ?? this.textColorHex,
      textBackgroundHex: textBackgroundHex ?? this.textBackgroundHex,
      textShowBackground: textShowBackground ?? this.textShowBackground,
      textShowBorder: textShowBorder ?? this.textShowBorder,
    );
  }
}
