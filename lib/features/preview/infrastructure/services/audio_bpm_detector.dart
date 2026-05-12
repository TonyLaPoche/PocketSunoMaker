import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class AudioBpmDetector {
  Future<double?> detectBpm({
    required String audioPath,
    Duration analysisWindow = const Duration(seconds: 90),
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
      analysisWindow.inSeconds.toString(),
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
        const Duration(seconds: 20),
      );
    } on Object {
      return null;
    }
    final String output = '${result.stdout ?? ''}\n${result.stderr ?? ''}';
    final List<_DbSample> samples = _parseRmsTimeline(output);
    if (samples.length < 24) {
      return null;
    }
    return _estimateBpm(samples);
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

  List<_DbSample> _parseRmsTimeline(String output) {
    final RegExp timeExp = RegExp(r'pts_time:([0-9]+(?:\.[0-9]+)?)');
    final RegExp rmsExp = RegExp(
      r'lavfi\.astats\.Overall\.RMS_level=([-]?[0-9]+(?:\.[0-9]+)?)',
    );
    double? currentTime;
    final List<_DbSample> result = <_DbSample>[];
    for (final String rawLine in const LineSplitter().convert(output)) {
      final String line = rawLine.trim();
      final RegExpMatch? tm = timeExp.firstMatch(line);
      if (tm != null) {
        currentTime = double.tryParse(tm.group(1)!);
      }
      final RegExpMatch? rm = rmsExp.firstMatch(line);
      if (rm == null || currentTime == null) {
        continue;
      }
      final double? db = double.tryParse(rm.group(1)!);
      if (db == null || !db.isFinite || db < -90) {
        continue;
      }
      result.add(_DbSample(timeSec: currentTime, rmsDb: db));
    }
    return result;
  }

  double? _estimateBpm(List<_DbSample> samples) {
    final List<double> dbValues = samples.map((s) => s.rmsDb).toList();
    final double mean = dbValues.reduce((a, b) => a + b) / dbValues.length;
    final double variance =
        dbValues
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        dbValues.length;
    final double std = math.sqrt(variance).clamp(0.001, 100.0);
    final List<double> thresholds = <double>[
      mean + std * 0.65,
      mean + std * 0.45,
      mean + std * 0.30,
    ];
    for (final double threshold in thresholds) {
      final List<double> peaks = _extractPeakTimes(samples, threshold);
      final double? bpm = _bpmFromPeaks(peaks);
      if (bpm != null) {
        return bpm;
      }
    }
    return null;
  }

  List<double> _extractPeakTimes(List<_DbSample> samples, double thresholdDb) {
    const double minSpacingSec = 0.22;
    final List<double> peakTimes = <double>[];
    double lastPeak = -999;
    for (int i = 1; i < samples.length - 1; i++) {
      final _DbSample a = samples[i - 1];
      final _DbSample b = samples[i];
      final _DbSample c = samples[i + 1];
      final bool localMax = b.rmsDb >= a.rmsDb && b.rmsDb > c.rmsDb;
      if (!localMax || b.rmsDb < thresholdDb) {
        continue;
      }
      if (b.timeSec - lastPeak < minSpacingSec) {
        continue;
      }
      peakTimes.add(b.timeSec);
      lastPeak = b.timeSec;
    }
    return peakTimes;
  }

  double? _bpmFromPeaks(List<double> peakTimes) {
    if (peakTimes.length < 6) {
      return null;
    }
    final List<double> bpms = <double>[];
    for (int i = 1; i < peakTimes.length; i++) {
      final double dt = peakTimes[i] - peakTimes[i - 1];
      if (dt < 0.25 || dt > 1.6) {
        continue;
      }
      double bpm = 60.0 / dt;
      while (bpm < 70) {
        bpm *= 2;
      }
      while (bpm > 180) {
        bpm /= 2;
      }
      bpms.add(bpm);
    }
    if (bpms.length < 5) {
      return null;
    }
    bpms.sort();
    final double median = bpms[bpms.length ~/ 2];
    return median.clamp(70.0, 180.0);
  }
}

class _DbSample {
  const _DbSample({required this.timeSec, required this.rmsDb});

  final double timeSec;
  final double rmsDb;
}
