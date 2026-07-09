import 'package:flutter/material.dart';
import 'package:edge_sense/constants/theme.dart';

class StepCard extends StatelessWidget {
  final int stepCount;
  final String sessionId;

  const StepCard({
    super.key,
    required this.stepCount,
    required this.sessionId,
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
            const Text('Steps', style: AppTheme.styleCardTitle), // 20sp Bold
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('👣 ', style: TextStyle(fontSize: 24)),
                Text(
                  '$stepCount',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.colorTextDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Current Session: ', style: AppTheme.styleLabel),
                Text(
                  sessionId,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.colorTextDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
