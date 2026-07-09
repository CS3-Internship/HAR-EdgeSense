import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:edge_sense/screens/dashboard_screen.dart';
import 'package:edge_sense/config/network_config.dart';
import 'package:edge_sense/constants/theme.dart';
import 'package:edge_sense/services/foreground_task_handler.dart';
import 'package:edge_sense/screens/system_information_screen.dart';
import 'package:edge_sense/widgets/prediction_card.dart';
import 'package:edge_sense/widgets/step_card.dart';
import 'package:edge_sense/widgets/system_info_button.dart';

class HomePage extends StatefulWidget {
  final String sessionId;

  const HomePage({super.key, required this.sessionId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ValueNotifier<AppState> _appStateNotifier = ValueNotifier<AppState>(
    const AppState(
      serviceRunning: false,
      wifiName: 'Loading...',
      deviceIp: 'Loading...',
      gatewayIp: 'Loading...',
      subnetMask: 'Loading...',
      isServerConnected: false,
      accelX: 0.0,
      accelY: 0.0,
      accelZ: 0.0,
      gyroX: 0.0,
      gyroY: 0.0,
      gyroZ: 0.0,
    ),
  );

  void _updateAppState() {
    _appStateNotifier.value = AppState(
      serviceRunning: _serviceRunning,
      wifiName: _wifiName,
      deviceIp: _deviceIp,
      gatewayIp: _gatewayIp,
      subnetMask: _subnetMask,
      isServerConnected: _isServerConnected,
      accelX: _accelX,
      accelY: _accelY,
      accelZ: _accelZ,
      gyroX: _gyroX,
      gyroY: _gyroY,
      gyroZ: _gyroZ,
    );
  }

  void _recordActivityPrediction(DateTime time, String rawActivity) async {
    if (_prefs == null) return;
    final String activityKey = _mapActivity(rawActivity);
    final String dateStr = "${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}";

    // Store daily total
    final String prefKey = "activity_duration_${dateStr}_$activityKey";
    final int currentSeconds = _prefs!.getInt(prefKey) ?? 0;
    await _prefs!.setInt(prefKey, currentSeconds + 1);

    // Store hourly breakdown
    final String hourStr = time.hour.toString().padLeft(2, '0');
    final String hourlyKey = "activity_hourly_${dateStr}_${hourStr}_$activityKey";
    final int currentHourlySeconds = _prefs!.getInt(hourlyKey) ?? 0;
    await _prefs!.setInt(hourlyKey, currentHourlySeconds + 1);
  }

  String _mapActivity(String raw) {
    final upper = raw.toUpperCase();
    if (upper.contains('WALK')) return 'Walking';
    if (upper.contains('SIT')) return 'Sitting';
    if (upper.contains('STAND')) return 'Standing';
    if (upper.contains('LAY')) return 'Laying';
    return 'Sitting';
  }

  bool _serviceRunning = false;
  String _lastTime = '--:--:--';
  int _successCount = 0;
  int _failCount = 0;

  double _accelX = 0.0, _accelY = 0.0, _accelZ = 0.0;
  double _gyroX = 0.0, _gyroY = 0.0, _gyroZ = 0.0;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Timer? _sensorSamplingTimer;
  Timer? _sensorForwardTimer;
  final List<Map<String, dynamic>> _collectedReadings = [];

  String _predictedActivity = 'Collecting data...';
  double _predictionConfidence = 0.0;
  String _predictionStatus = 'collecting';

  int _stepCount = 0;
  SharedPreferences? _prefs;

  final String serverUrl = sendBatchUrl;

  bool _hasReceivedFirstPrediction = false;
  String _lastValidActivity = '';
  double _lastValidConfidence = 0.0;
  String _lastValidPredictionTime = '--:--:--';
  int _currentSamples = 0;
  bool _isServerConnected = false;

  String _wifiName = 'Loading...';
  String _deviceIp = 'Loading...';
  String _gatewayIp = 'Loading...';
  String _subnetMask = 'Loading...';
  bool _isLocationPermissionGranted = false;
  Timer? _networkInfoTimer;

  String _formatTime12h(DateTime dt) {
    int hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  @override
  void initState() {
    super.initState();
    _initPrefs();
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestPermissions();
      _initService();
      final running = await FlutterForegroundTask.isRunningService;
      if (mounted) {
        setState(() => _serviceRunning = running);
        if (running) {
          _startSensorStreams();
        }
        _updateAppState();
      }
    });

    _networkInfoTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (Platform.isAndroid) {
        final status = await Permission.locationWhenInUse.status;
        if (mounted) {
          setState(() {
            _isLocationPermissionGranted = status.isGranted;
          });
        }
      }
      await _updateNetworkInfo();
    });
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadStepsForSession();
    _seedInitialDataIfEmpty();
  }

  String _getCurrentDateStr() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  void _checkAndResetStepsIfNeeded() {
    if (_prefs == null) return;
    const dateKey = 'steps_date';
    final currentDateStr = _getCurrentDateStr();
    
    String? savedDate = _prefs!.getString(dateKey);
    if (savedDate == null) {
      _prefs!.setString(dateKey, currentDateStr);
      
      // Migration from session-specific date keys & 24-hour timers
      final sessionTimeKey = 'steps_start_time_${widget.sessionId}';
      final sessionDateKey = 'steps_date_${widget.sessionId}';
      
      final savedSessionDate = _prefs!.getString(sessionDateKey);
      final oldTime = _prefs!.getInt(sessionTimeKey);
      
      bool shouldReset = false;
      if (savedSessionDate != null && savedSessionDate != currentDateStr) {
        shouldReset = true;
      } else if (oldTime != null) {
        final oldDate = DateTime.fromMillisecondsSinceEpoch(oldTime);
        final oldDateStr = "${oldDate.year}-${oldDate.month.toString().padLeft(2, '0')}-${oldDate.day.toString().padLeft(2, '0')}";
        if (oldDateStr != currentDateStr) {
          shouldReset = true;
        }
      }
      
      if (shouldReset) {
        _resetAllSessionsSteps();
      } else {
        _syncStepsToTask();
      }
      
      _prefs!.remove(sessionTimeKey);
      _prefs!.remove(sessionDateKey);
      return;
    }

    if (savedDate != currentDateStr) {
      _prefs!.setString(dateKey, currentDateStr);
      _resetAllSessionsSteps();
    }
  }

  void _loadStepsForSession() {
    if (_prefs == null) return;
    _checkAndResetStepsIfNeeded();
    final key = 'steps_${widget.sessionId}';
    setState(() {
      _stepCount = _prefs!.getInt(key) ?? 0;
    });
    _syncStepsToTask();
  }

  void _syncStepsToTask() {
    if (_prefs == null) return;
    const dateKey = 'steps_date';
    final stepsDate = _prefs!.getString(dateKey) ?? _getCurrentDateStr();
    FlutterForegroundTask.sendDataToTask({
      'step_count': _stepCount,
      'steps_date': stepsDate,
    });
  }



  void _resetAllSessionsSteps() {
    if (_prefs == null) return;
    final keys = _prefs!.getKeys();
    for (final key in keys) {
      if (key.startsWith('steps_') && !key.startsWith('steps_date') && !key.startsWith('steps_start_time')) {
        _prefs!.setInt(key, 0);
      }
    }
    setState(() {
      _stepCount = 0;
    });
    _syncStepsToTask();
  }

  void _seedInitialDataIfEmpty() async {
    if (_prefs == null) return;
    final bool hasData = _prefs!.getBool('has_seeded_data') ?? false;
    if (!hasData) {
      final now = DateTime.now();
      final int currentWeekday = now.weekday;
      final DateTime monday = now.subtract(Duration(days: currentWeekday - 1));

      final defaultWeeklyDurations = {
        'Walking': [15, 20, 10, 25, 15, 20, 15],
        'Sitting': [25, 30, 20, 35, 25, 25, 20],
        'Running': [5, 0, 10, 0, 10, 15, 5],
        'Standing': [10, 12, 8, 15, 10, 12, 8],
      };

      for (int i = 0; i < 7; i++) {
        final DateTime day = monday.add(Duration(days: i));
        if (day.isAfter(now)) continue;
        
        final String dateStr = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
        
        defaultWeeklyDurations.forEach((activity, durations) {
          final int minutes = durations[i];
          final String prefKey = "activity_duration_${dateStr}_$activity";
          _prefs!.setInt(prefKey, minutes * 60);
        });
      }

      await _prefs!.setBool('has_seeded_data', true);
      _updateAppState();
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _stopSensorStreams();
    _networkInfoTimer?.cancel();
    _appStateNotifier.dispose();
    super.dispose();
  }

  void _onReceiveTaskData(Object data) {
    if (data is Map<String, dynamic>) {
      final now = DateTime.now();
      setState(() {
        _successCount = data['successCount'] ?? _successCount;
        _failCount = data['failCount'] ?? _failCount;
        if (data['status'] == 'ok') {
          _isServerConnected = true;
          _lastTime = _formatTime12h(now);
          
          _predictionStatus = data['prediction_status'] ?? _predictionStatus;
          _predictedActivity = data['activity'] ?? _predictedActivity;
          _predictionConfidence = (data['confidence'] as num?)?.toDouble() ?? _predictionConfidence;
          
          if (_predictionStatus == 'predicted') {
            _hasReceivedFirstPrediction = true;
            _lastValidActivity = _predictedActivity;
            _lastValidConfidence = _predictionConfidence;
            _lastValidPredictionTime = _lastTime;
            _recordActivityPrediction(now, _predictedActivity);
          } else if (_predictionStatus == 'collecting') {
            final match = RegExp(r'Collecting \((\d+)/128\)').firstMatch(_predictedActivity);
            if (match != null) {
              _currentSamples = int.tryParse(match.group(1) ?? '0') ?? 0;
            }
          }

          if (data.containsKey('steps_date')) {
            final stepsDate = data['steps_date'] as String?;
            if (_prefs != null && stepsDate != null) {
              final savedDate = _prefs!.getString('steps_date');
              if (savedDate != stepsDate) {
                _prefs!.setString('steps_date', stepsDate);
                _resetAllSessionsSteps();
              }
            }
          }
          if (data.containsKey('step_count')) {
            _stepCount = data['step_count'] ?? _stepCount;
            _checkAndResetStepsIfNeeded();
            if (_prefs != null) {
              _prefs!.setInt('steps_${widget.sessionId}', _stepCount);
            }
          }
        } else {
          _isServerConnected = false;
          
          if (data.containsKey('steps_date')) {
            final stepsDate = data['steps_date'] as String?;
            if (_prefs != null && stepsDate != null) {
              final savedDate = _prefs!.getString('steps_date');
              if (savedDate != stepsDate) {
                _prefs!.setString('steps_date', stepsDate);
                _resetAllSessionsSteps();
              }
            }
          }
          if (data.containsKey('step_count')) {
            _stepCount = data['step_count'] ?? _stepCount;
            _checkAndResetStepsIfNeeded();
            if (_prefs != null) {
              _prefs!.setInt('steps_${widget.sessionId}', _stepCount);
            }
          }
        }
      });
      _updateAppState();
    }
  }

  void _startSensorStreams() {
    _collectedReadings.clear();

    _accelSub = accelerometerEventStream().listen((event) {
      _accelX = event.x;
      _accelY = event.y;
      _accelZ = event.z;
      if (mounted) {
        setState(() {});
        _updateAppState();
      }
    });

    _gyroSub = gyroscopeEventStream().listen((event) {
      _gyroX = event.x;
      _gyroY = event.y;
      _gyroZ = event.z;
      if (mounted) {
        setState(() {});
        _updateAppState();
      }
    });

    _sensorSamplingTimer = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) {
        final now = DateTime.now();
        _collectedReadings.add({
          'time': now.toString(),
          'accelerometer': {
            'x': double.parse(_accelX.toStringAsFixed(4)),
            'y': double.parse(_accelY.toStringAsFixed(4)),
            'z': double.parse(_accelZ.toStringAsFixed(4)),
          },
          'gyroscope': {
            'x': double.parse(_gyroX.toStringAsFixed(4)),
            'y': double.parse(_gyroY.toStringAsFixed(4)),
            'z': double.parse(_gyroZ.toStringAsFixed(4)),
          }
        });
      }
    );

    _sensorForwardTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (_collectedReadings.isEmpty) return;
        
        final List<Map<String, dynamic>> batch = List<Map<String, dynamic>>.from(_collectedReadings);
        _collectedReadings.clear();

        FlutterForegroundTask.sendDataToTask({
          'session': widget.sessionId,
          'readings': batch,
          'server_url': sendBatchUrl,
        });
      },
    );
  }

  void _stopSensorStreams() {
    _accelSub?.cancel();
    _accelSub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
    _sensorSamplingTimer?.cancel();
    _sensorSamplingTimer = null;
    _sensorForwardTimer?.cancel();
    _sensorForwardTimer = null;
  }

  Future<void> _requestPermissions() async {
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      
      await _checkAndRequestLocationPermission();
    }
  }

  Future<void> _checkAndRequestLocationPermission() async {
    try {
      var status = await Permission.locationWhenInUse.status;
      if (status.isDenied) {
        status = await Permission.locationWhenInUse.request();
      }
      setState(() {
        _isLocationPermissionGranted = status.isGranted;
      });
      await _updateNetworkInfo();
    } catch (e) {
      debugPrint('Error checking location permission: $e');
    }
  }

  Future<void> _updateNetworkInfo() async {
    final info = NetworkInfo();
    String? wifi;
    String? ip;
    String? gateway;
    String? subnet;

    try {
      if (_isLocationPermissionGranted) {
        wifi = await info.getWifiName();
        if (wifi != null) {
          wifi = wifi.replaceAll('"', '');
        }
      } else {
        wifi = 'Location permission required to display Wi-Fi information.';
      }
    } catch (e) {
      wifi = 'Location permission required to display Wi-Fi information.';
      debugPrint('Error getting wifi name: $e');
    }

    try {
      ip = await info.getWifiIP();
    } catch (e) {
      ip = 'Unavailable';
    }

    try {
      gateway = await info.getWifiGatewayIP();
    } catch (e) {
      gateway = 'Unavailable';
    }

    try {
      subnet = await info.getWifiSubmask();
    } catch (e) {
      subnet = 'Unavailable';
    }

    if (mounted) {
      setState(() {
        _wifiName = wifi ?? (_isLocationPermissionGranted ? 'Unavailable' : 'Location permission required to display Wi-Fi information.');
        _deviceIp = ip ?? 'Unavailable';
        _gatewayIp = gateway ?? 'Unavailable';
        _subnetMask = subnet ?? 'Unavailable';
      });
      _updateAppState();
    }
  }

  void _initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'edgesense_foreground',
        channelName: 'EdgeSense Service',
        channelDescription:
            'Shows when EdgeSense is sending data to the server.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startService() async {
    final ServiceRequestResult result;
    if (!kIsWeb) {
      if (await FlutterForegroundTask.isRunningService) {
        result = await FlutterForegroundTask.restartService();
      } else {
        result = await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'EdgeSense [${widget.sessionId}]',
          notificationText: 'Sending sensor data every second...',
          callback: startCallback,
        );
      }
    } else {
      result = const ServiceRequestFailure(
        error: 'Foreground service is not supported on Web',
      );
    }

    if (result is ServiceRequestSuccess) {
      _startSensorStreams();

      Future.delayed(const Duration(milliseconds: 300), () {
        String? stepsDate;
        if (_prefs != null) {
          stepsDate = _prefs!.getString('steps_date');
        }
        stepsDate ??= _getCurrentDateStr();
        FlutterForegroundTask.sendDataToTask({
          'session': widget.sessionId,
          'step_count': _stepCount,
          'steps_date': stepsDate,
          'server_url': sendBatchUrl,
        });
      });

      if (mounted) {
        setState(() {
          _serviceRunning = true;
          _hasReceivedFirstPrediction = false;
          _lastValidActivity = '';
          _lastValidConfidence = 0.0;
          _lastValidPredictionTime = '--:--:--';
          _currentSamples = 0;
          _isServerConnected = false;
        });
        _updateAppState();
      }
    }
  }

  Future<void> _stopService() async {
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestSuccess) {
      _stopSensorStreams();
      if (mounted) {
        setState(() {
          _serviceRunning = false;
          _successCount = 0;
          _failCount = 0;
          _hasReceivedFirstPrediction = false;
          _lastValidActivity = '';
          _lastValidConfidence = 0.0;
          _lastValidPredictionTime = '--:--:--';
          _currentSamples = 0;
          _isServerConnected = false;
        });
        _updateAppState();
      }
    }
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _serviceRunning ? null : _startService,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppTheme.colorPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade100,
                disabledForegroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Text('Start Service'),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _serviceRunning ? _stopService : null,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppTheme.colorError,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade100,
                disabledForegroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Text('Stop Service'),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.colorBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'EdgeSense',
                          style: AppTheme.styleTitle,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Human Activity Recognition',
                          style: AppTheme.styleSubtitle,
                        ),
                      ],
                    ),
                  ),
                  SystemInfoButton(
                    sessionId: widget.sessionId,
                    appStateNotifier: _appStateNotifier,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PredictionCard(
                        hasReceivedFirstPrediction: _hasReceivedFirstPrediction,
                        lastValidActivity: _lastValidActivity,
                        lastValidConfidence: _lastValidConfidence,
                        lastValidPredictionTime: _lastValidPredictionTime,
                        currentSamples: _currentSamples,
                      ),
                      const SizedBox(height: 16),
                      StepCard(
                        stepCount: _stepCount,
                        sessionId: widget.sessionId,
                      ),
                      const SizedBox(height: 16),
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
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DashboardScreen(sessionId: widget.sessionId),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.dashboard,
                                    color: AppTheme.colorPrimary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: const [
                                        Text(
                                          'Dashboard',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.colorTextDark,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'View Activity Analytics',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppTheme.colorTextGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    color: AppTheme.colorTextGrey,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 24.0),
              child: _buildActionButtons(),
            ),
          ],
        ),
      ),
    );
  }
}
