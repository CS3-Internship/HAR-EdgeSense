import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A single Wi-Fi scan result: SSID and signal strength (dBm).
class WifiScanResult {
  final String ssid;
  final int rssi;

  const WifiScanResult({required this.ssid, required this.rssi});
}

/// Actively drives Wi-Fi network switching via Android's WifiNetworkSpecifier
/// API, rather than passively hoping WifiNetworkSuggestion causes Android to
/// roam on its own — which it largely won't do while the current network is
/// still functioning, even if weak. Android only.
class WifiConnector {
  static const MethodChannel _channel = MethodChannel('com.edgesense.app/wifi');

  /// Requests a connection to [ssid] and binds the app's network traffic to it
  /// once established. Returns true on success. Shows a one-time system
  /// "Allow this app to connect?" dialog the first time for a given SSID.
  static Future<bool> connectTo(String ssid, String password) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final status = await _channel.invokeMethod<int>('connectToWifi', {
        'ssid': ssid,
        'password': password,
      });
      return status == 0;
    } catch (e) {
      debugPrint('WifiConnector.connectTo failed: $e');
      return false;
    }
  }

  /// Returns currently-visible Wi-Fi networks. May reflect the system's own
  /// recent ambient scan rather than a freshly-triggered one, since Android
  /// throttles explicit scan requests from non-system apps.
  static Future<List<WifiScanResult>> scan() async {
    if (kIsWeb || !Platform.isAndroid) return [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('scanWifi');
      if (raw == null) return [];
      return raw
          .whereType<Map>()
          .map((entry) => WifiScanResult(
                ssid: (entry['ssid'] as String?) ?? '',
                rssi: (entry['rssi'] as int?) ?? -127,
              ))
          .where((r) => r.ssid.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('WifiConnector.scan failed: $e');
      return [];
    }
  }
}
