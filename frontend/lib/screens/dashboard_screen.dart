import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:edge_sense/config/network_config.dart';
import 'package:edge_sense/constants/theme.dart';
import 'package:edge_sense/screens/activity_detail_screen.dart';
import 'package:edge_sense/widgets/activity_pie_chart.dart';

class DashboardScreen extends StatefulWidget {
  final String sessionId;
  const DashboardScreen({super.key, required this.sessionId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // State variables
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, int> _activityCounts = {};
  int _totalPredictions = 0;
  Timer? _refreshTimer;

  // Colors mapping for activities
  final Map<String, Color> _activityColors = {
    'Walking': AppTheme.colorPrimary,
    'Sitting': AppTheme.colorWarning,
    'Laying': AppTheme.colorError,
    'laying': AppTheme.colorError,
    'Standing': AppTheme.colorSuccess,
    'Walking Upstairs': Colors.blue,
    'Walking Downstairs': Colors.lightBlue,
  };

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    // Auto-refresh every 5 seconds so it updates live
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchDashboardData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Fetch today's aggregated prediction analytics from edge server
  Future<void> _fetchDashboardData() async {
    try {
      final response =
          await http.get(Uri.parse(
              '$serverBaseUrl/dashboard/today?session_id=${widget.sessionId}'));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;

        final Map<String, int> rawCounts = {};
        if (decoded['activity_counts'] != null) {
          decoded['activity_counts'].forEach((key, value) {
            final int count = (value as num).toInt();
            if (count > 0) {
              rawCounts[key] = count;
            }
          });
        }

        if (mounted) {
          setState(() {
            _activityCounts = rawCounts;
            _totalPredictions =
                (decoded['total_predictions'] as num?)?.toInt() ?? 0;
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

  // Format prediction count back into human-readable duration
  String _formatDuration(int predictionCount) {
    // Each prediction window ≈ 2.56 seconds
    final int totalSeconds = (predictionCount * 2.56).toInt();
    final int totalMinutes = totalSeconds ~/ 60;
    final int remainingSeconds = totalSeconds % 60;

    if (totalMinutes > 0) {
      final int hours = totalMinutes ~/ 60;
      final int mins = totalMinutes % 60;
      if (hours > 0) {
        return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
      } else {
        return remainingSeconds > 0
            ? '${mins}m ${remainingSeconds}s'
            : '${mins}m';
      }
    } else {
      return '${remainingSeconds}s';
    }
  }

  // Navigate to detailed activity screen
  void _navigateToDetail(String activityName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityDetailScreen(
          activityName: activityName,
          sessionId: widget.sessionId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate total duration from all counts
    final int totalCount =
        _activityCounts.values.fold(0, (sum, val) => sum + val);
    final String totalDuration = _formatDuration(totalCount);

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
          "Dashboard",
          style: TextStyle(
            color: AppTheme.colorTextDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.colorTextDark),
            onPressed: _fetchDashboardData,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _totalPredictions == 0
                  ? _buildEmptyState()
                  : _buildDashboardContent(totalDuration),
    );
  }

  // Error screen state widget
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: AppTheme.colorTextGrey),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.colorTextDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchDashboardData,
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

  // Empty data screen state widget
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.show_chart, size: 72, color: AppTheme.colorTextGrey),
            const SizedBox(height: 24),
            const Text(
              "No activity data for today.",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.colorTextDark,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Start streaming sensor data from the Home screen to see today's activity predictions here.",
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.colorTextGrey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _fetchDashboardData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.colorPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text("Check Again"),
            )
          ],
        ),
      ),
    );
  }

  // Main dashboard layout builder
  Widget _buildDashboardContent(String totalDuration) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Activity Distribution Card
            Container(
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
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: Text(
                      'Activity Distribution',
                      style: AppTheme.styleCardTitle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Today',
                      style: AppTheme.styleSubtitle,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: ActivityPieChart(
                      data: _activityCounts.map(
                          (key, value) => MapEntry(key, value.toDouble())),
                      colors: _activityColors,
                      totalDuration: totalDuration,
                      onTapSection: _navigateToDetail,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(color: AppTheme.colorBorder, height: 1),
                  const SizedBox(height: 16),
                  _buildLegendList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Legend list builder for activity details
  Widget _buildLegendList() {
    return Column(
      children: _activityCounts.keys.map((key) {
        final int count = _activityCounts[key] ?? 0;
        final String durationStr = _formatDuration(count);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _navigateToDetail(key),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 8.0, horizontal: 8.0),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _activityColors[key] ?? Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    key,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.colorTextGrey,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    durationStr,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.colorTextDark,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
