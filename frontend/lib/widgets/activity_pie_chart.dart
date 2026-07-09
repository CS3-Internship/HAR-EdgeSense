import 'dart:math';
import 'package:flutter/material.dart';
import 'package:edge_sense/constants/theme.dart';

class ActivityPieChart extends StatelessWidget {
  final Map<String, double> data;
  final Map<String, Color> colors;
  final String totalDuration;
  final Function(String) onTapSection;

  const ActivityPieChart({
    super.key,
    required this.data,
    required this.colors,
    required this.totalDuration,
    required this.onTapSection,
  });

  @override
  Widget build(BuildContext context) {
    const double chartSize = 240.0;
    const double ringThickness = 42.0;
    final double total = data.values.fold(0.0, (sum, val) => sum + val);

    return GestureDetector(
      onTapUp: (details) {
        final RenderBox renderBox = context.findRenderObject() as RenderBox;
        final Offset localPosition = details.localPosition;
        final Size size = renderBox.size;
        final Offset center = Offset(size.width / 2, size.height / 2);

        final double dx = localPosition.dx - center.dx;
        final double dy = localPosition.dy - center.dy;
        final double distance = sqrt(dx * dx + dy * dy);
        final double outerRadius = chartSize / 2;
        final double innerRadius = outerRadius - ringThickness;

        if (distance > outerRadius || distance < innerRadius) return;

        double angle = atan2(dy, dx);
        double normalizedAngle = (angle + pi / 2) % (2 * pi);
        if (normalizedAngle < 0) normalizedAngle += 2 * pi;

        if (total == 0) return;

        double currentAngle = 0;
        String? selectedKey;

        data.forEach((key, val) {
          if (selectedKey != null) return;
          final double sweepAngle = (val / total) * 2 * pi;
          if (normalizedAngle >= currentAngle &&
              normalizedAngle <= currentAngle + sweepAngle) {
            selectedKey = key;
          }
          currentAngle += sweepAngle;
        });

        if (selectedKey != null) {
          onTapSection(selectedKey!);
        }
      },
      child: SizedBox(
        width: chartSize,
        height: chartSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: chartSize,
              height: chartSize,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: CustomPaint(
                size: const Size(chartSize, chartSize),
                painter: _PieChartPainter(
                  data: data,
                  colors: colors,
                  thickness: ringThickness,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TODAY',
                  style: AppTheme.styleLabel.copyWith(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: AppTheme.colorTextGrey,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  totalDuration,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.colorTextDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Activity',
                  style: AppTheme.styleSubtitle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final Map<String, double> data;
  final Map<String, Color> colors;
  final double thickness;

  _PieChartPainter({
    required this.data,
    required this.colors,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double total = data.values.fold(0, (sum, val) => sum + val);
    if (total == 0) return;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - thickness / 2;

    final Paint slicePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    double startAngle = -pi / 2;
    data.forEach((key, val) {
      final double sweepAngle = (val / total) * 2 * pi;
      slicePaint.color = colors[key] ?? Colors.grey;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        slicePaint,
      );
      startAngle += sweepAngle;
    });

    final Paint separatorPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..isAntiAlias = true;

    startAngle = -pi / 2;
    data.forEach((key, val) {
      final double sweepAngle = (val / total) * 2 * pi;
      final Offset lineEnd = Offset(
        center.dx + radius * cos(startAngle),
        center.dy + radius * sin(startAngle),
      );
      canvas.drawLine(center, lineEnd, separatorPaint);
      startAngle += sweepAngle;
    });

    final Paint innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius - thickness / 2, innerPaint);

    final Paint borderPaint = Paint()
      ..color = AppTheme.colorBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius + thickness / 2, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
