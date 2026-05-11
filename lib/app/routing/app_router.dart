import 'package:flutter/material.dart';

import '../../features/project/presentation/pages/project_home_page.dart';

final class AppRouter {
  static const String homeRoute = '/';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case homeRoute:
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const ProjectHomePage(),
          settings: settings,
        );
    }
  }
}
