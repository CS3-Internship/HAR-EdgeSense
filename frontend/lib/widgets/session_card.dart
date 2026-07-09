import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:edge_sense/constants/theme.dart';
import 'package:edge_sense/screens/session_screen.dart';

class SessionCard extends StatelessWidget {
  final String sessionId;
  final bool serviceRunning;

  const SessionCard({
    super.key,
    required this.sessionId,
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
        padding: const EdgeInsets.all(8.0), // 8 px inside cards
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Session Details', style: AppTheme.styleCardTitle), // 20sp Bold
            const SizedBox(height: 12),
            _infoRow('Session', sessionId),
            const SizedBox(height: 8),
            _infoRow('Status', serviceRunning ? 'Running' : 'Stopped'),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.colorBorder, height: 1),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await FlutterForegroundTask.stopService();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const SessionScreen()),
                      (route) => false,
                    );
                  }
                },
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Log Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.colorError,
                  side: const BorderSide(color: AppTheme.colorError, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
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
