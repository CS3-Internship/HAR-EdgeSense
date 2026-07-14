import 'package:flutter/material.dart';

import 'package:edge_sense/constants/theme.dart';
import 'package:edge_sense/screens/hotspot_settings_screen.dart';
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
  final String previousServer;

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
    this.previousServer = '',
  });
}

class SystemInformationScreen extends StatelessWidget {
  final String sessionId;
  final ValueNotifier<AppState> appStateNotifier;
  final Future<String> Function() onMigrateNow;

  const SystemInformationScreen({
    super.key,
    required this.sessionId,
    required this.appStateNotifier,
    required this.onMigrateNow,
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
                    previousServer: state.previousServer,
                  ),
                  const SizedBox(height: 16),
                  _MigrateNowCard(onMigrateNow: onMigrateNow),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.colorCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.colorBorder, width: 1),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HotspotSettingsScreen()),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(Icons.wifi_tethering, color: AppTheme.colorPrimary, size: 24),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Edge Server Networks',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.colorTextDark,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Register hotspots so Wi-Fi roams between them',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.colorTextGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios, color: AppTheme.colorTextGrey, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
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

/// Manual, on-demand migration trigger for testing: checks whatever edge
/// server the phone is actually connected to right now and migrates the
/// session to it immediately, without waiting for automatic Wi-Fi-switch
/// detection or the fuzzy urgency score to rise.
class _MigrateNowCard extends StatefulWidget {
  final Future<String> Function() onMigrateNow;

  const _MigrateNowCard({required this.onMigrateNow});

  @override
  State<_MigrateNowCard> createState() => _MigrateNowCardState();
}

class _MigrateNowCardState extends State<_MigrateNowCard> {
  bool _running = false;
  String? _result;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
    });
    final message = await widget.onMigrateNow();
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.colorCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.colorBorder, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Migration (Testing)', style: AppTheme.styleCardTitle),
            const SizedBox(height: 8),
            const Text(
              'Checks the edge server for whatever network you\'re actually on right now '
              'and migrates the session to it immediately — for testing without waiting on '
              'automatic detection.',
              style: AppTheme.styleLabel,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync, size: 18),
                label: Text(_running ? 'Migrating…' : 'Migrate Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.colorPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.colorPrimary.withValues(alpha: 0.6),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(_result!, style: AppTheme.styleLabel),
            ],
          ],
        ),
      ),
    );
  }
}
