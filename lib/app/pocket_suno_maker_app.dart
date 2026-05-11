import 'package:flutter/material.dart';

import 'routing/app_router.dart';
import 'theme/app_theme.dart';

class PocketSunoMakerApp extends StatelessWidget {
  const PocketSunoMakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketSunoMaker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      onGenerateRoute: AppRouter.generateRoute,
      initialRoute: AppRouter.homeRoute,
    );
  }
}
