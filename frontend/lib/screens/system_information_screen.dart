import 'package:flutter/material.dart';

import 'package:edge_sense/constants/theme.dart';
import 'package:edge_sense/widgets/network_info_card.dart';
import 'package:edge_sense/widgets/sensor_card.dart';
import 'package:edge_sense/widgets/session_card.dart';

class AppState {
  final bool serviceRunning;
  final String wifiName;
  final String deviceIp;
  final String gatewayIp;
  final String subnetMask;
  final bool isServerConnected;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final String handoverMessage;
  final String handoverSignalLabel;
  final double handoverUrgency;
  final bool handoverInProgress;

  const AppState({
    required this.serviceRunning,
    required this.wifiName,
    required this.deviceIp,
    required this.gatewayIp,
    required this.subnetMask,
    required this.isServerConnected,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    this.handoverMessage = 'Connecting…',
    this.handoverSignalLabel = 'Good',
    this.handoverUrgency = 0.0,
    this.handoverInProgress = false,
  });
}

class SystemInformationScreen extends StatelessWidget {
  final String sessionId;
  final ValueNotifier<AppState> appStateNotifier;

  const SystemInformationScreen({
    super.key,
    required this.sessionId,
    required this.appStateNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppState>(
      valueListenable: appStateNotifier,
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: AppTheme.colorBackground,
          appBar: AppBar(
            backgroundColor: AppTheme.colorBackground,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppTheme.colorTextDark),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              "System Information",
              style: TextStyle(
                color: AppTheme.colorTextDark,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NetworkInfoCard(
                    wifiName: state.wifiName,
                    deviceIp: state.deviceIp,
                    gatewayIp: state.gatewayIp,
                    subnetMask: state.subnetMask,
                    isServerConnected: state.isServerConnected,
                    serviceRunning: state.serviceRunning,
                    handoverMessage: state.handoverMessage,
                    handoverSignalLabel: state.handoverSignalLabel,
                    handoverUrgency: state.handoverUrgency,
                    handoverInProgress: state.handoverInProgress,
                  ),
                  const SizedBox(height: 16),
                  SessionCard(
                    sessionId: sessionId,
                    serviceRunning: state.serviceRunning,
                  ),
                  const SizedBox(height: 16),
                  SensorCard(
                    title: 'Accelerometer',
                    unit: 'm/s²',
                    x: state.accelX,
                    y: state.accelY,
                    z: state.accelZ,
                    icon: Icons.speed,
                  ),
                  const SizedBox(height: 16),
                  SensorCard(
                    title: 'Gyroscope',
                    unit: 'rad/s',
                    x: state.gyroX,
                    y: state.gyroY,
                    z: state.gyroZ,
                    icon: Icons.rotate_right,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
