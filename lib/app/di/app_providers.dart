import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';

final Provider<AppLogger> appLoggerProvider = Provider<AppLogger>(
  (Ref ref) => const AppLogger(),
);
