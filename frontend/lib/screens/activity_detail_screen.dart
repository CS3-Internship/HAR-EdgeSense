import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:edge_sense/config/network_config.dart';
import 'package:edge_sense/constants/theme.dart';

class ActivityDetailScreen extends StatefulWidget {
  final String activityName;
  final String sessionId;

  const ActivityDetailScreen({
    super.key,
    required this.activityName,
    required this.sessionId,
  });

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  String _totalTime = '0s';
  Map<String, int> _hourlyData = {};
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchActivityData();
    // Auto-refresh every 5 seconds so it updates live
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchActivityData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchActivityData() async {
    try {
      final response = await http.get(
        Uri.parse(
            '$serverBaseUrl/statistics/today/${widget.activityName}?session_id=${widget.sessionId}'),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;

        final Map<String, int> hourly = {};
        if (decoded['hourly_distribution'] != null) {
          decoded['hourly_distribution'].forEach((key, value) {
            hourly[key] = (value as num).toInt();
          });
        }

        final String durationStr =
            decoded['duration_string'] ?? '0s';

        if (mounted) {
          setState(() {
            _hourlyData = hourly;
            _totalTime = durationStr;
            _errorMessage = null;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Server error: HTTP ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Cannot connect to Edge Server';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Color activityColor = AppTheme.colorPrimary;
    switch (widget.activityName) {
      case 'Walking':
        activityColor = AppTheme.colorPrimary;
        break;
      case 'Sitting':
        activityColor = AppTheme.colorWarning;
        break;
      case 'Laying':
        activityColor = AppTheme.colorError;
        break;
      case 'Standing':
        activityColor = AppTheme.colorSuccess;
        break;
      case 'Walking Upstairs':
        activityColor = Colors.blue;
        break;
      case 'Walking Downstairs':
        activityColor = Colors.lightBlue;
        break;
    }

    if (_isLoading) {
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
          title: Text(
            widget.activityName,
            style: const TextStyle(
              color: AppTheme.colorTextDark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
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
          title: Text(
            widget.activityName,
            style: const TextStyle(
              color: AppTheme.colorTextDark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off,
                  size: 64, color: AppTheme.colorTextGrey),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.colorTextDark,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _fetchActivityData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.colorPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    // Find max for bar scaling
    int maxCount = 0;
    for (int h = 0; h < 24; h++) {
      final String hourStr = h.toString().padLeft(2, '0');
      final int count = _hourlyData[hourStr] ?? 0;
      if (count > maxCount) maxCount = count;
    }

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
        title: Text(
          widget.activityName,
          style: const TextStyle(
            color: AppTheme.colorTextDark,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Total Time Spent
              Text(
                'Total Time Spent Today',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.colorTextGrey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _totalTime,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.colorTextDark,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 48),

              // Bar Graph Header
              const Text(
                'Hourly Breakdown',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.colorTextDark,
                ),
              ),
              const SizedBox(height: 24),

              // Horizontally scrollable 24-hour bar chart
              SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(24, (index) {
                      final String hourStr =
                          index.toString().padLeft(2, '0');
                      final int count = _hourlyData[hourStr] ?? 0;
                      final double heightFactor =
                          maxCount > 0 ? (count / maxCount) : 0.0;

                      return Container(
                        width: 42,
                        margin:
                            const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Count above bar
                            Text(
                              count > 0 ? '$count' : '-',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.colorTextDark,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 8),
                            // The Bar
                            Container(
                              height: 110 * heightFactor,
                              decoration: BoxDecoration(
                                color: activityColor.withValues(
                                    alpha: 0.85),
                                borderRadius:
                                    const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                                boxShadow: [
                                  if (count > 0)
                                    BoxShadow(
                                      color:
                                          activityColor.withValues(
                                              alpha: 0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, -1),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Hour Label
                            Text(
                              hourStr,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.colorTextGrey,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
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
