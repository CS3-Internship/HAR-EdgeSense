import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(EdgeSenseTaskHandler());
}

class EdgeSenseTaskHandler extends TaskHandler {
  String _serverUrl = "";

  int _successCount = 0;
  int _failCount = 0;

  String _session = 'Unknown';
  final List<Map<String, dynamic>> _pendingReadings = [];

  double _smoothMag = 0.0;
  bool _aboveThreshold = false;
  int _lastStepTimeMs = 0;
  int _stepCount = 0;
  String _stepsDate = "";

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint("Server URL: $_serverUrl");
    debugPrint("EdgeSenseTaskHandler started (starter: ${starter.name})");
  }
  @override
  void onRepeatEvent(DateTime timestamp) async {
    // Check daily calendar reset
    if (_stepsDate.isNotEmpty) {
      final now = DateTime.now();
      final currentDateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      if (currentDateStr != _stepsDate) {
        _stepCount = 0;
        _stepsDate = currentDateStr;

        // Send updated state to main task immediately
        FlutterForegroundTask.sendDataToMain({
          'status': 'ok',
          'time': DateTime.now().toString(),
          'successCount': _successCount,
          'failCount': _failCount,
          'step_count': _stepCount,
          'steps_date': _stepsDate,
        });
      }
    }

    if (_serverUrl.isEmpty) {
      debugPrint("Server URL not received yet.");
      return;
    }

    if (_pendingReadings.isEmpty) return;

    final now = DateTime.now();
    final List<Map<String, dynamic>> readingsToSend = List<Map<String, dynamic>>.from(_pendingReadings);
    _pendingReadings.clear();

    final payload = jsonEncode({
      'session': _session,
      'device': 'EdgeSense',
      'step_count': _stepCount,
      'readings': readingsToSend,
    });

    try {
      debugPrint('--- HTTP REQUEST LOG ---');
      debugPrint('Request URL: $_serverUrl');
      debugPrint('Endpoint: /send_batch');
      debugPrint('Payload size: ${readingsToSend.length} samples');
      debugPrint('Step Count: $_stepCount');

      final res = await http.post(
        Uri.parse(_serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );

      debugPrint('Status Code: ${res.statusCode}');
      debugPrint('Response Body: ${res.body}');
      debugPrint('------------------------');

      if (res.statusCode == 200) {
        _successCount++;
        
        String activity = 'Collecting...';
        double confidence = 0.0;
        String predictionStatus = 'collecting';
        
        try {
          final resData = jsonDecode(res.body);
          predictionStatus = resData['status'] ?? 'collecting';
          if (predictionStatus == 'predicted') {
            activity = resData['activity'] ?? 'Unknown';
            confidence = (resData['confidence'] as num?)?.toDouble() ?? 0.0;
            
            final hour = now.hour.toString().padLeft(2, '0');
            final minute = now.minute.toString().padLeft(2, '0');
            final second = now.second.toString().padLeft(2, '0');
            final timeStr = "$hour:$minute:$second";
            final confidencePercent = confidence * 100;
            
            debugPrint('====================================');
            debugPrint('HAR PREDICTION');
            debugPrint('====================================');
            debugPrint('Time      : $timeStr');
            debugPrint('Session   : $_session');
            debugPrint('Activity  : $activity');
            debugPrint('Confidence: ${confidencePercent.toStringAsFixed(1)}%');
            debugPrint('====================================');
          } else if (predictionStatus == 'collecting') {
            final samples = resData['samples'] ?? 0;
            activity = 'Collecting ($samples/128)';
          }
        } catch (e) {
          debugPrint('Error parsing response body: $e');
        }

        FlutterForegroundTask.updateService(
          notificationTitle: 'EdgeSense [$_session]',
          notificationText: 'Steps: $_stepCount • Activity: $activity (${(confidence * 100).toStringAsFixed(1)}%)',
        );

        FlutterForegroundTask.sendDataToMain({
          'status': 'ok',
          'time': now.toString(),
          'successCount': _successCount,
          'failCount': _failCount,
          'prediction_status': predictionStatus,
          'activity': activity,
          'confidence': confidence,
          'step_count': _stepCount,
          'steps_date': _stepsDate,
        });
      } else {
        _failCount++;
        FlutterForegroundTask.sendDataToMain({
          'status': 'error',
          'error': 'HTTP ${res.statusCode}',
          'successCount': _successCount,
          'failCount': _failCount,
          'step_count': _stepCount,
          'steps_date': _stepsDate,
        });
      }
    } catch (e) {
      _failCount++;
      debugPrint('--- HTTP REQUEST ERROR ---');
      debugPrint('Request URL: $_serverUrl');
      debugPrint('Endpoint: /send_batch');
      debugPrint('Error: $e');
      debugPrint('--------------------------');
      
      final displayError = e.toString().contains('SocketException') || e.toString().contains('Connection timed out')
          ? 'Cannot connect to Edge Server'
          : 'Error: ${e.toString()}';

      FlutterForegroundTask.sendDataToMain({
        'status': 'error',
        'error': displayError,
        'successCount': _successCount,
        'failCount': _failCount,
        'step_count': _stepCount,
        'steps_date': _stepsDate,
      });
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('EdgeSenseTaskHandler destroyed (isTimeout: $isTimeout)');
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map<String, dynamic>) {
      _session = data['session'] ?? _session;
      if (data.containsKey('server_url')) {
        _serverUrl = data['server_url'];
        debugPrint("Received Server URL: $_serverUrl");
      }
      if (data.containsKey('readings')) {
        final List<dynamic> readingsList = data['readings'];
        for (var r in readingsList) {
          if (r is Map) {
            _pendingReadings.add(Map<String, dynamic>.from(r));
            _processStepCounting(r);
          }
        }
      }
      if (data.containsKey('step_count')) {
        _stepCount = data['step_count'] ?? _stepCount;
      }
      if (data.containsKey('steps_date')) {
        _stepsDate = data['steps_date'] ?? _stepsDate;
      }
    }
  }

  void _processStepCounting(Map r) {
    try {
      final acc = r['accelerometer'];
      if (acc == null) return;

      final double ax = (acc['x'] as num).toDouble();
      final double ay = (acc['y'] as num).toDouble();
      final double az = (acc['z'] as num).toDouble();

      final double mag = math.sqrt(ax * ax + ay * ay + az * az);

      if (_smoothMag == 0.0) {
        _smoothMag = mag;
      } else {
        _smoothMag = 0.15 * mag + 0.85 * _smoothMag;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_smoothMag > 10.8) {
        if (!_aboveThreshold) {
          _aboveThreshold = true;
          if (nowMs - _lastStepTimeMs > 350) {
            _stepCount++;
            _lastStepTimeMs = nowMs;
          }
        }
      } else if (_smoothMag < 9.5) {
        _aboveThreshold = false;
      }
    } catch (e) {
      debugPrint('Error in step counting: $e');
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('Notification button pressed: $id');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    debugPrint('Notification dismissed');
  }
}
