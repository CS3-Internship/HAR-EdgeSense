import 'package:flutter/material.dart';
import 'package:edge_sense/constants/theme.dart';

class ConnectionCard extends StatelessWidget {
  final bool isServerConnected;
  final bool serviceRunning;

  const ConnectionCard({
    super.key,
    required this.isServerConnected,
    required this.serviceRunning,
  });

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Connection Status', style: AppTheme.styleCardTitle),
            const SizedBox(height: 12),
            _statusRow('Edge Server Status', isServerConnected ? '🟢 Connected' : '🔴 Disconnected'),
            const SizedBox(height: 8),
            _statusRow('Foreground Service', serviceRunning ? '🟢 Running' : '🔴 Stopped'),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTheme.styleLabel),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.colorTextDark,
          ),
        ),
      ],
    );
  }
}
