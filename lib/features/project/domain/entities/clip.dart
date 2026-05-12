enum TextAnimationType { none, fade, slideUp, slideDown, zoom }

enum VisualEffectType { glitch, shake, rgbSplit, flash, vhs }

enum AudioEffectType { censorBeep, distortion, stutter }

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
    this.textEntryAnimation = TextAnimationType.none,
    this.textExitAnimation = TextAnimationType.none,
    this.textEntryFade = false,
    this.textEntrySlideUp = false,
    this.textEntrySlideDown = false,
    this.textEntryZoom = false,
    this.textExitFade = false,
    this.textExitSlideUp = false,
    this.textExitSlideDown = false,
    this.textExitZoom = false,
    this.textEntryDurationMs = 300,
    this.textExitDurationMs = 300,
    this.textEntryOffsetPx = 28.0,
    this.textExitOffsetPx = 28.0,
    this.textEntryScale = 0.70,
    this.textExitScale = 0.70,
    this.karaokeEnabled = false,
    this.karaokeFillColorHex = '#FEE440',
    this.karaokeLeadInMs = 0,
    this.karaokeSweepDurationMs = 2500,
    this.visualEffectType,
    this.audioEffectType,
    this.effectIntensity = 0.6,
    this.effectShakeAmplitudePx = 8.0,
    this.effectShakeFrequencyHz = 34.0,
    this.effectShakeAudioSync = false,
    this.effectShakeAutoBpm = false,
    this.effectShakeDetectedBpm = 120.0,
    this.effectGlitchTearStrength = 0.55,
    this.effectGlitchNoiseAmount = 0.45,
    this.effectGlitchColorAHex = '#00E5FF',
    this.effectGlitchColorBHex = '#FF00E6',
    this.effectGlitchAutoColors = true,
    this.effectGlitchAudioSync = false,
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
  final TextAnimationType textEntryAnimation;
  final TextAnimationType textExitAnimation;
  final bool textEntryFade;
  final bool textEntrySlideUp;
  final bool textEntrySlideDown;
  final bool textEntryZoom;
  final bool textExitFade;
  final bool textExitSlideUp;
  final bool textExitSlideDown;
  final bool textExitZoom;
  final int textEntryDurationMs;
  final int textExitDurationMs;
  final double textEntryOffsetPx;
  final double textExitOffsetPx;
  final double textEntryScale;
  final double textExitScale;
  final bool karaokeEnabled;
  final String karaokeFillColorHex;
  final int karaokeLeadInMs;
  final int karaokeSweepDurationMs;
  final VisualEffectType? visualEffectType;
  final AudioEffectType? audioEffectType;
  final double effectIntensity;
  final double effectShakeAmplitudePx;
  final double effectShakeFrequencyHz;
  final bool effectShakeAudioSync;
  final bool effectShakeAutoBpm;
  final double effectShakeDetectedBpm;
  final double effectGlitchTearStrength;
  final double effectGlitchNoiseAmount;
  final String effectGlitchColorAHex;
  final String effectGlitchColorBHex;
  final bool effectGlitchAutoColors;
  final bool effectGlitchAudioSync;

  bool get hasEntryFade =>
      textEntryFade || textEntryAnimation == TextAnimationType.fade;
  bool get hasEntrySlideUp =>
      textEntrySlideUp || textEntryAnimation == TextAnimationType.slideUp;
  bool get hasEntrySlideDown =>
      textEntrySlideDown || textEntryAnimation == TextAnimationType.slideDown;
  bool get hasEntryZoom =>
      textEntryZoom || textEntryAnimation == TextAnimationType.zoom;

  bool get hasExitFade =>
      textExitFade || textExitAnimation == TextAnimationType.fade;
  bool get hasExitSlideUp =>
      textExitSlideUp || textExitAnimation == TextAnimationType.slideUp;
  bool get hasExitSlideDown =>
      textExitSlideDown || textExitAnimation == TextAnimationType.slideDown;
  bool get hasExitZoom =>
      textExitZoom || textExitAnimation == TextAnimationType.zoom;

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
    TextAnimationType? textEntryAnimation,
    TextAnimationType? textExitAnimation,
    bool? textEntryFade,
    bool? textEntrySlideUp,
    bool? textEntrySlideDown,
    bool? textEntryZoom,
    bool? textExitFade,
    bool? textExitSlideUp,
    bool? textExitSlideDown,
    bool? textExitZoom,
    int? textEntryDurationMs,
    int? textExitDurationMs,
    double? textEntryOffsetPx,
    double? textExitOffsetPx,
    double? textEntryScale,
    double? textExitScale,
    bool? karaokeEnabled,
    String? karaokeFillColorHex,
    int? karaokeLeadInMs,
    int? karaokeSweepDurationMs,
    VisualEffectType? visualEffectType,
    AudioEffectType? audioEffectType,
    double? effectIntensity,
    double? effectShakeAmplitudePx,
    double? effectShakeFrequencyHz,
    bool? effectShakeAudioSync,
    bool? effectShakeAutoBpm,
    double? effectShakeDetectedBpm,
    double? effectGlitchTearStrength,
    double? effectGlitchNoiseAmount,
    String? effectGlitchColorAHex,
    String? effectGlitchColorBHex,
    bool? effectGlitchAutoColors,
    bool? effectGlitchAudioSync,
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
      textEntryAnimation: textEntryAnimation ?? this.textEntryAnimation,
      textExitAnimation: textExitAnimation ?? this.textExitAnimation,
      textEntryFade: textEntryFade ?? this.textEntryFade,
      textEntrySlideUp: textEntrySlideUp ?? this.textEntrySlideUp,
      textEntrySlideDown: textEntrySlideDown ?? this.textEntrySlideDown,
      textEntryZoom: textEntryZoom ?? this.textEntryZoom,
      textExitFade: textExitFade ?? this.textExitFade,
      textExitSlideUp: textExitSlideUp ?? this.textExitSlideUp,
      textExitSlideDown: textExitSlideDown ?? this.textExitSlideDown,
      textExitZoom: textExitZoom ?? this.textExitZoom,
      textEntryDurationMs: textEntryDurationMs ?? this.textEntryDurationMs,
      textExitDurationMs: textExitDurationMs ?? this.textExitDurationMs,
      textEntryOffsetPx: textEntryOffsetPx ?? this.textEntryOffsetPx,
      textExitOffsetPx: textExitOffsetPx ?? this.textExitOffsetPx,
      textEntryScale: textEntryScale ?? this.textEntryScale,
      textExitScale: textExitScale ?? this.textExitScale,
      karaokeEnabled: karaokeEnabled ?? this.karaokeEnabled,
      karaokeFillColorHex: karaokeFillColorHex ?? this.karaokeFillColorHex,
      karaokeLeadInMs: karaokeLeadInMs ?? this.karaokeLeadInMs,
      karaokeSweepDurationMs:
          karaokeSweepDurationMs ?? this.karaokeSweepDurationMs,
      visualEffectType: visualEffectType ?? this.visualEffectType,
      audioEffectType: audioEffectType ?? this.audioEffectType,
      effectIntensity: effectIntensity ?? this.effectIntensity,
      effectShakeAmplitudePx:
          effectShakeAmplitudePx ?? this.effectShakeAmplitudePx,
      effectShakeFrequencyHz:
          effectShakeFrequencyHz ?? this.effectShakeFrequencyHz,
      effectShakeAudioSync: effectShakeAudioSync ?? this.effectShakeAudioSync,
      effectShakeAutoBpm: effectShakeAutoBpm ?? this.effectShakeAutoBpm,
      effectShakeDetectedBpm:
          effectShakeDetectedBpm ?? this.effectShakeDetectedBpm,
      effectGlitchTearStrength:
          effectGlitchTearStrength ?? this.effectGlitchTearStrength,
      effectGlitchNoiseAmount:
          effectGlitchNoiseAmount ?? this.effectGlitchNoiseAmount,
      effectGlitchColorAHex: effectGlitchColorAHex ?? this.effectGlitchColorAHex,
      effectGlitchColorBHex: effectGlitchColorBHex ?? this.effectGlitchColorBHex,
      effectGlitchAutoColors:
          effectGlitchAutoColors ?? this.effectGlitchAutoColors,
      effectGlitchAudioSync: effectGlitchAudioSync ?? this.effectGlitchAudioSync,
    );
  }
}
