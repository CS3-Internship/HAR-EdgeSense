import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:edge_sense/screens/session_screen.dart';
import 'package:edge_sense/config/network_service.dart';
import 'package:edge_sense/services/hotspot_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await initializeNetwork();
    FlutterForegroundTask.initCommunicationPort();
    // Android doesn't remember an app's Wi-Fi network suggestions across a
    // reinstall/data-clear, so re-register any saved edge-server hotspots
    // every cold start. Not awaited — shouldn't delay showing the UI.
    unawaited(HotspotManager.applySaved());
  }

  runApp(const EdgeSenseApp());
}

class EdgeSenseApp extends StatelessWidget {
  const EdgeSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EdgeSense',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        cardTheme: CardThemeData(
          color: const Color(0xFFF5F5F5),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const SessionScreen(),
    );
  }
}