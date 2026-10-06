import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'services/radar_service.dart';
import 'services/storage_service.dart';
import 'ui/radar_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  // Request permissions if needed
  if (Platform.isAndroid) {
    FlutterForegroundTask.requestNotificationPermission();
  }

  final storageService = StorageService();
  final radarService = RadarService(storageService: storageService);
  await radarService.init();

  runApp(MemeRadarApp(
    storageService: storageService,
    radarService: radarService,
  ));
}

class MemeRadarApp extends StatelessWidget {
  final StorageService storageService;
  final RadarService radarService;

  const MemeRadarApp({
    super.key,
    required this.storageService,
    required this.radarService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meme Radar',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E676),
          brightness: Brightness.dark,
          surface: const Color(0xFF141416),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0E10),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141416),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1B1D21),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: WithForegroundTask(
        child: RadarScreen(
          storageService: storageService,
          radarService: radarService,
        ),
      ),
    );
  }
}
