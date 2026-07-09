import 'package:flutter/material.dart';
import 'package:edge_sense/constants/theme.dart';

class SensorCard extends StatelessWidget {
  final String title;
  final String unit;
  final double x;
  final double y;
  final double z;
  final IconData icon;

  const SensorCard({
    super.key,
    required this.title,
    required this.unit,
    required this.x,
    required this.y,
    required this.z,
    required this.icon,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppTheme.colorPrimary, size: 20),
                    const SizedBox(width: 8),
                    Text(title, style: AppTheme.styleCardTitle), // 20sp Bold
                  ],
                ),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.colorTextGrey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildSensorAxis('X', x),
                _buildSensorAxis('Y', y),
                _buildSensorAxis('Z', z),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorAxis(String axis, double value) {
    return Expanded(
      child: Column(
        children: [
          Text(axis, style: AppTheme.styleLabel),
          const SizedBox(height: 4),
          Text(
            value.toStringAsFixed(3),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.colorTextDark,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
