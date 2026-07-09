import 'package:flutter/material.dart';
import 'package:edge_sense/constants/theme.dart';

class PredictionCard extends StatelessWidget {
  final bool hasReceivedFirstPrediction;
  final String lastValidActivity;
  final double lastValidConfidence;
  final String lastValidPredictionTime;
  final int currentSamples;

  const PredictionCard({
    super.key,
    required this.hasReceivedFirstPrediction,
    required this.lastValidActivity,
    required this.lastValidConfidence,
    required this.lastValidPredictionTime,
    required this.currentSamples,
  });

  @override
  Widget build(BuildContext context) {
    Color indicatorColor = Colors.grey;
    Widget activityIcon;
    String activityName;
    String confidenceText;
    String timeText = lastValidPredictionTime;

    if (!hasReceivedFirstPrediction) {
      indicatorColor = Colors.grey;
      activityIcon = const Icon(Icons.hourglass_empty_rounded, size: 40, color: Colors.grey);
      activityName = 'Collecting Initial Sensor Data...';
      confidenceText = 'Samples: $currentSamples / 128';
    } else {
      final act = lastValidActivity.toUpperCase();
      String emoji = '❓';
      String name = lastValidActivity;
      if (act.contains('WALKING_UPSTAIRS')) {
        emoji = '🚶';
        name = 'Walking Upstairs';
        indicatorColor = AppTheme.colorPrimary;
      } else if (act.contains('WALKING_DOWNSTAIRS')) {
        emoji = '🚶';
        name = 'Walking Downstairs';
        indicatorColor = AppTheme.colorPrimary;
      } else if (act.contains('WALKING')) {
        emoji = '🚶';
        name = 'Walking';
        indicatorColor = AppTheme.colorPrimary;
      } else if (act.contains('SITTING')) {
        emoji = '🪑';
        name = 'Sitting';
        indicatorColor = AppTheme.colorWarning;
      } else if (act.contains('STANDING')) {
        emoji = '🧍';
        name = 'Standing';
        indicatorColor = AppTheme.colorSuccess;
      } else if (act.contains('LAYING')) {
        emoji = '🛏';
        name = 'Laying';
        indicatorColor = Colors.blueGrey;
      } else {
        emoji = '❓';
        name = lastValidActivity;
        indicatorColor = Colors.grey;
      }

      activityIcon = Text(emoji, style: const TextStyle(fontSize: 40));
      activityName = name;
      confidenceText = '${(lastValidConfidence * 100).toStringAsFixed(1)} %';
    }

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                color: indicatorColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0), // 8 px inside cards
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Current Activity', style: AppTheme.styleCardTitle), // 20sp Bold
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          activityIcon,
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activityName,
                                  style: hasReceivedFirstPrediction
                                      ? AppTheme.stylePrediction
                                      : const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.colorTextDark,
                                        ),
                                ),
                                const SizedBox(height: 4),
                                if (hasReceivedFirstPrediction)
                                  Row(
                                    children: [
                                      const Text('Confidence: ', style: AppTheme.styleLabel),
                                      Text(
                                        confidenceText,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.colorPrimary,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Text(confidenceText, style: AppTheme.styleConfidence),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: AppTheme.colorBorder, height: 1),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Last Updated', style: AppTheme.styleLabel),
                          Text(
                            timeText,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
