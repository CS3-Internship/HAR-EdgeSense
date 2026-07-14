import 'package:flutter/material.dart';
import 'package:edge_sense/constants/theme.dart';
import 'package:edge_sense/config/network_config.dart';

class NetworkInfoCard extends StatelessWidget {
  final String wifiName;
  final String deviceIp;
  final String gatewayIp;
  final String subnetMask;
  final bool isServerConnected;
  final bool serviceRunning;
  final String handoverMessage;
  final String handoverSignalLabel;
  final double handoverUrgency;
  final bool handoverInProgress;
  final String previousServer;

  const NetworkInfoCard({
    super.key,
    required this.wifiName,
    required this.deviceIp,
    required this.gatewayIp,
    required this.subnetMask,
    required this.isServerConnected,
    required this.serviceRunning,
    this.handoverMessage = '',
    this.handoverSignalLabel = 'Good',
    this.handoverUrgency = 0.0,
    this.handoverInProgress = false,
    this.previousServer = '',
  });

  @override
  Widget build(BuildContext context) {
    final displayServer = serverBaseUrl.replaceFirst('http://', '').replaceFirst('https://', '');
    
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.colorCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.colorBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0), // 8 px inside cards
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Network Information', style: AppTheme.styleCardTitle), // 20sp Bold
            const SizedBox(height: 12),
            _networkRow('Wi-Fi Name', wifiName),
            const SizedBox(height: 8),
            _networkRow('Device IP', deviceIp),
            const SizedBox(height: 8),
            _networkRow('Gateway', gatewayIp),
            const SizedBox(height: 8),
            _networkRow('Subnet Mask', subnetMask),
            const SizedBox(height: 8),
            _networkRow('Edge Server', displayServer),
            const SizedBox(height: 8),
            _networkRow('Edge Server Status', isServerConnected ? '🟢 Connected' : '🔴 Disconnected'),
            const SizedBox(height: 8),
            _networkRow('Foreground Service', serviceRunning ? '🟢 Running' : '🔴 Stopped'),
            const SizedBox(height: 8),
            _networkRow('AI Engine', serviceRunning ? '🟢 Monitoring Live Data' : '🔴 Stopped'),
            if (handoverMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              _networkRow('Signal Quality', '${_signalIcon()} $handoverSignalLabel (${handoverUrgency.toStringAsFixed(0)})'),
              const SizedBox(height: 8),
              _networkRow('Handover Status', handoverInProgress ? '🔄 $handoverMessage' : handoverMessage),
            ],
            if (previousServer.isNotEmpty) ...[
              const SizedBox(height: 8),
              _networkRow('Previous Edge Server', previousServer.replaceFirst('http://', '').replaceFirst('https://', '')),
            ],
          ],
        ),
      ),
    );
  }

  String _signalIcon() {
    if (handoverSignalLabel == 'Poor') return '🔴';
    if (handoverSignalLabel == 'Fair') return '🟡';
    return '🟢';
  }

  Widget _networkRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTheme.styleLabel),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.colorTextDark,
            ),
          ),
        ),
      ],
    );
  }
}
