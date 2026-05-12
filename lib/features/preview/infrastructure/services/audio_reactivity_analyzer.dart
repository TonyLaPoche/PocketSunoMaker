import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class AudioReactivityAnalyzer {
  Future<AudioReactivityProfile?> analyze({
    required String audioPath,
    Duration maxDuration = const Duration(minutes: 8),
  }) async {
    final File source = File(audioPath);
    if (!source.existsSync()) {
      return null;
    }
    final String ffmpeg = _resolveFfmpegCommand();
    final List<String> args = <String>[
      '-hide_banner',
      '-v',
      'info',
      '-ss',
      '0',
      '-t',
      maxDuration.inSeconds.toString(),
      '-i',
      audioPath,
      '-vn',
      '-af',
      'astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level',
      '-f',
      'null',
      '-',
    ];
    ProcessResult result;
    try {
      result = await Process.run(ffmpeg, args).timeout(
        const Duration(seconds: 30),
      );
    } on Object {
      return null;
    }
    final String output = '${result.stdout ?? ''}\n${result.stderr ?? ''}';
    final List<_DbSample> samples = _parseRms(output);
    if (samples.length < 24) {
      return null;
    }
    final List<double> normalized = _normalize(samples.map((e) => e.db).toList());
    return AudioReactivityProfile(
      timesSec: samples.map((e) => e.timeSec).toList(growable: false),
      levels: normalized,
    );
  }

  String _resolveFfmpegCommand() {
    const List<String> preferredPaths = <String>[
      '/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg',
      '/usr/local/opt/ffmpeg-full/bin/ffmpeg',
    ];
    for (final String path in preferredPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return 'ffmpeg';
  }

  List<_DbSample> _parseRms(String output) {
    final RegExp timeExp = RegExp(r'pts_time:([0-9]+(?:\.[0-9]+)?)');
    final RegExp rmsExp = RegExp(
      r'lavfi\.astats\.Overall\.RMS_level=([-]?[0-9]+(?:\.[0-9]+)?)',
    );
    final List<_DbSample> result = <_DbSample>[];
    double? time;
    for (final String rawLine in const LineSplitter().convert(output)) {
      final String line = rawLine.trim();
      final RegExpMatch? tm = timeExp.firstMatch(line);
      if (tm != null) {
        time = double.tryParse(tm.group(1)!);
      }
      final RegExpMatch? rm = rmsExp.firstMatch(line);
      if (rm == null || time == null) {
        continue;
      }
      final double? db = double.tryParse(rm.group(1)!);
      if (db == null || !db.isFinite || db <= -90) {
        continue;
      }
      result.add(_DbSample(timeSec: time, db: db));
    }
    return result;
  }

  List<double> _normalize(List<double> dbValues) {
    final List<double> linear = dbValues
        .map((double db) => math.pow(10.0, db / 20.0).toDouble())
        .toList(growable: false);
    final List<double> sorted = List<double>.from(linear)..sort();
    final double floor = _quantile(sorted, 0.12);
    final double ceil = _quantile(sorted, 0.96);
    final double span = (ceil - floor).abs() < 1e-8 ? 1.0 : (ceil - floor);
    return linear.map((double v) {
      final double n = ((v - floor) / span).clamp(0.0, 1.0);
      return math.pow(n, 0.75).toDouble();
    }).toList(growable: false);
  }

  double _quantile(List<double> sorted, double q) {
    if (sorted.isEmpty) {
      return 0;
    }
    final double idx = (sorted.length - 1) * q.clamp(0.0, 1.0);
    final int lo = idx.floor();
    final int hi = idx.ceil();
    if (lo == hi) {
      return sorted[lo];
    }
    final double t = idx - lo;
    return sorted[lo] * (1 - t) + sorted[hi] * t;
  }
}

class AudioReactivityProfile {
  const AudioReactivityProfile({required this.timesSec, required this.levels});

  final List<double> timesSec;
  final List<double> levels;

  double levelAtSec(double sec) {
    if (timesSec.isEmpty || levels.isEmpty) {
      return 0.0;
    }
    if (sec <= timesSec.first) {
      return levels.first;
    }
    final int last = timesSec.length - 1;
    if (sec >= timesSec[last]) {
      return levels[last];
    }
    int i = 0;
    while (i < last && timesSec[i + 1] < sec) {
      i++;
    }
    final double t0 = timesSec[i];
    final double t1 = timesSec[i + 1];
    final double v0 = levels[i];
    final double v1 = levels[i + 1];
    final double denom = (t1 - t0).abs() < 1e-6 ? 1.0 : (t1 - t0);
    final double alpha = ((sec - t0) / denom).clamp(0.0, 1.0);
    return (v0 * (1 - alpha) + v1 * alpha).clamp(0.0, 1.0);
  }
}

class _DbSample {
  const _DbSample({required this.timeSec, required this.db});
  final double timeSec;
  final double db;
}
