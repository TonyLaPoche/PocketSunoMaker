import 'dart:convert';
import 'dart:io';

import '../../domain/entities/project.dart';
import '../../domain/entities/clip.dart';
import '../../domain/entities/track.dart';

class LocalProjectDataSource {
  const LocalProjectDataSource();

  Future<Project> createProject(String projectName) async {
    return Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: projectName,
      fps: 30,
      canvasWidth: 1920,
      canvasHeight: 1080,
      durationMs: 0,
      tracks: const <Track>[],
    );
  }

  Future<Project> loadProject(String path) async {
    final File file = File(path);
    final String rawContent = await file.readAsString();
    final Object? decoded = jsonDecode(rawContent);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid .psm content');
    }
    return _projectFromJson(decoded);
  }

  Future<void> saveProject({
    required Project project,
    required String path,
  }) async {
    final File file = File(path);
    await file.create(recursive: true);
    final Map<String, dynamic> payload = _projectToJson(project);
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(payload));
  }

  Map<String, dynamic> _projectToJson(Project project) {
    return <String, dynamic>{
      'schemaVersion': 1,
      'id': project.id,
      'name': project.name,
      'fps': project.fps,
      'canvasWidth': project.canvasWidth,
      'canvasHeight': project.canvasHeight,
      'durationMs': project.durationMs,
      'tracks': project.tracks.map(_trackToJson).toList(growable: false),
    };
  }

  Map<String, dynamic> _trackToJson(Track track) {
    return <String, dynamic>{
      'id': track.id,
      'type': track.type.name,
      'index': track.index,
      'name': track.name,
      'clips': track.clips.map(_clipToJson).toList(growable: false),
    };
  }

  Map<String, dynamic> _clipToJson(Clip clip) {
    return <String, dynamic>{
      'id': clip.id,
      'assetPath': clip.assetPath,
      'timelineStartMs': clip.timelineStartMs,
      'sourceInMs': clip.sourceInMs,
      'sourceOutMs': clip.sourceOutMs,
      'opacity': clip.opacity,
      'speed': clip.speed,
      'volume': clip.volume,
      'scale': clip.scale,
      'rotationDeg': clip.rotationDeg,
      'textContent': clip.textContent,
      'textPosXPx': clip.textPosXPx,
      'textPosYPx': clip.textPosYPx,
      'textFontSizePx': clip.textFontSizePx,
      'textFontFamily': clip.textFontFamily,
      'textBold': clip.textBold,
      'textItalic': clip.textItalic,
      'textColorHex': clip.textColorHex,
      'textBackgroundHex': clip.textBackgroundHex,
      'textShowBackground': clip.textShowBackground,
      'textShowBorder': clip.textShowBorder,
      'textEntryAnimation': clip.textEntryAnimation.name,
      'textExitAnimation': clip.textExitAnimation.name,
      'textEntryFade': clip.textEntryFade,
      'textEntrySlideUp': clip.textEntrySlideUp,
      'textEntrySlideDown': clip.textEntrySlideDown,
      'textEntryZoom': clip.textEntryZoom,
      'textExitFade': clip.textExitFade,
      'textExitSlideUp': clip.textExitSlideUp,
      'textExitSlideDown': clip.textExitSlideDown,
      'textExitZoom': clip.textExitZoom,
      'textEntryDurationMs': clip.textEntryDurationMs,
      'textExitDurationMs': clip.textExitDurationMs,
      'textEntryOffsetPx': clip.textEntryOffsetPx,
      'textExitOffsetPx': clip.textExitOffsetPx,
      'textEntryScale': clip.textEntryScale,
      'textExitScale': clip.textExitScale,
      'karaokeEnabled': clip.karaokeEnabled,
      'karaokeFillColorHex': clip.karaokeFillColorHex,
      'karaokeLeadInMs': clip.karaokeLeadInMs,
      'karaokeSweepDurationMs': clip.karaokeSweepDurationMs,
      'visualEffectType': clip.visualEffectType?.name,
      'audioEffectType': clip.audioEffectType?.name,
      'effectIntensity': clip.effectIntensity,
    };
  }

  Project _projectFromJson(Map<String, dynamic> json) {
    final List<dynamic> rawTracks =
        (json['tracks'] as List<dynamic>? ?? <dynamic>[]);
    return Project(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      fps: _asInt(json['fps'], fallback: 30),
      canvasWidth: _asInt(json['canvasWidth'], fallback: 1920),
      canvasHeight: _asInt(json['canvasHeight'], fallback: 1080),
      durationMs: _asInt(json['durationMs'], fallback: 0),
      tracks: rawTracks
          .whereType<Map<String, dynamic>>()
          .map(_trackFromJson)
          .toList(growable: false),
    );
  }

  Track _trackFromJson(Map<String, dynamic> json) {
    final List<dynamic> rawClips =
        (json['clips'] as List<dynamic>? ?? <dynamic>[]);
    final String rawType = json['type'] as String? ?? TrackType.video.name;
    final TrackType type = TrackType.values.firstWhere(
      (TrackType candidate) => candidate.name == rawType,
      orElse: () => TrackType.video,
    );

    return Track(
      id: json['id'] as String? ?? '',
      type: type,
      index: _asInt(json['index'], fallback: 0),
      name: json['name'] as String?,
      clips: rawClips
          .whereType<Map<String, dynamic>>()
          .map(_clipFromJson)
          .toList(growable: false),
    );
  }

  Clip _clipFromJson(Map<String, dynamic> json) {
    final TextAnimationType entryLegacy = _asTextAnimationType(
      json['textEntryAnimation'],
      fallback: TextAnimationType.none,
    );
    final TextAnimationType exitLegacy = _asTextAnimationType(
      json['textExitAnimation'],
      fallback: TextAnimationType.none,
    );
    final bool entryFade = _asBool(
      json['textEntryFade'],
      fallback: entryLegacy == TextAnimationType.fade,
    );
    final bool entrySlideUp = _asBool(
      json['textEntrySlideUp'],
      fallback: entryLegacy == TextAnimationType.slideUp,
    );
    final bool entrySlideDown = _asBool(
      json['textEntrySlideDown'],
      fallback: entryLegacy == TextAnimationType.slideDown,
    );
    final bool entryZoom = _asBool(
      json['textEntryZoom'],
      fallback: entryLegacy == TextAnimationType.zoom,
    );
    final bool exitFade = _asBool(
      json['textExitFade'],
      fallback: exitLegacy == TextAnimationType.fade,
    );
    final bool exitSlideUp = _asBool(
      json['textExitSlideUp'],
      fallback: exitLegacy == TextAnimationType.slideUp,
    );
    final bool exitSlideDown = _asBool(
      json['textExitSlideDown'],
      fallback: exitLegacy == TextAnimationType.slideDown,
    );
    final bool exitZoom = _asBool(
      json['textExitZoom'],
      fallback: exitLegacy == TextAnimationType.zoom,
    );
    final VisualEffectType? visualEffectType = _asVisualEffectType(
      json['visualEffectType'],
    );
    final AudioEffectType? audioEffectType = _asAudioEffectType(
      json['audioEffectType'],
    );

    return Clip(
      id: json['id'] as String? ?? '',
      assetPath: json['assetPath'] as String? ?? '',
      timelineStartMs: _asInt(json['timelineStartMs'], fallback: 0),
      sourceInMs: _asInt(json['sourceInMs'], fallback: 0),
      sourceOutMs: _asInt(json['sourceOutMs'], fallback: 0),
      opacity: _asDouble(json['opacity'], fallback: 1.0),
      speed: _asDouble(json['speed'], fallback: 1.0),
      volume: _asDouble(json['volume'], fallback: 1.0),
      scale: _asDouble(json['scale'], fallback: 1.0),
      rotationDeg: _asDouble(json['rotationDeg'], fallback: 0.0),
      textContent: json['textContent'] as String?,
      textPosXPx: _asDouble(json['textPosXPx'], fallback: 0.0),
      textPosYPx: _asDouble(json['textPosYPx'], fallback: 0.0),
      textFontSizePx: _asDouble(json['textFontSizePx'], fallback: 42.0),
      textFontFamily: json['textFontFamily'] as String? ?? 'Roboto',
      textBold: _asBool(json['textBold'], fallback: false),
      textItalic: _asBool(json['textItalic'], fallback: false),
      textColorHex: json['textColorHex'] as String? ?? '#FFFFFF',
      textBackgroundHex: json['textBackgroundHex'] as String? ?? '#000000',
      textShowBackground: _asBool(json['textShowBackground'], fallback: true),
      textShowBorder: _asBool(json['textShowBorder'], fallback: true),
      textEntryAnimation: entryLegacy,
      textExitAnimation: exitLegacy,
      textEntryFade: entryFade,
      textEntrySlideUp: entrySlideUp,
      textEntrySlideDown: entrySlideDown,
      textEntryZoom: entryZoom,
      textExitFade: exitFade,
      textExitSlideUp: exitSlideUp,
      textExitSlideDown: exitSlideDown,
      textExitZoom: exitZoom,
      textEntryDurationMs: _asInt(json['textEntryDurationMs'], fallback: 300),
      textExitDurationMs: _asInt(json['textExitDurationMs'], fallback: 300),
      textEntryOffsetPx: _asDouble(json['textEntryOffsetPx'], fallback: 28.0),
      textExitOffsetPx: _asDouble(json['textExitOffsetPx'], fallback: 28.0),
      textEntryScale: _asDouble(json['textEntryScale'], fallback: 0.70),
      textExitScale: _asDouble(json['textExitScale'], fallback: 0.70),
      karaokeEnabled: _asBool(json['karaokeEnabled'], fallback: false),
      karaokeFillColorHex: json['karaokeFillColorHex'] as String? ?? '#FEE440',
      karaokeLeadInMs: _asInt(json['karaokeLeadInMs'], fallback: 0),
      karaokeSweepDurationMs: _asInt(
        json['karaokeSweepDurationMs'],
        fallback: 2500,
      ),
      visualEffectType: visualEffectType,
      audioEffectType: audioEffectType,
      effectIntensity: _asDouble(json['effectIntensity'], fallback: 0.6),
    );
  }

  int _asInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  double _asDouble(Object? value, {required double fallback}) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  bool _asBool(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      if (value.toLowerCase() == 'true') {
        return true;
      }
      if (value.toLowerCase() == 'false') {
        return false;
      }
    }
    return fallback;
  }

  TextAnimationType _asTextAnimationType(
    Object? value, {
    required TextAnimationType fallback,
  }) {
    if (value is String) {
      for (final TextAnimationType type in TextAnimationType.values) {
        if (type.name == value) {
          return type;
        }
      }
    }
    return fallback;
  }

  VisualEffectType? _asVisualEffectType(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final VisualEffectType type in VisualEffectType.values) {
      if (type.name == value) {
        return type;
      }
    }
    return null;
  }

  AudioEffectType? _asAudioEffectType(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final AudioEffectType type in AudioEffectType.values) {
      if (type.name == value) {
        return type;
      }
    }
    return null;
  }
}
