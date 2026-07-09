import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads the current Wi-Fi signal strength (RSSI, in dBm) via a small native
/// platform channel. Android only — iOS does not expose RSSI to apps, and on
/// unsupported platforms this simply returns null so callers can fall back to
/// latency-only signal quality estimation.
class WifiRssi {
  static const MethodChannel _channel = MethodChannel('com.edgesense.app/wifi');

  static Future<int?> getRssi() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<int>('getRssi');
      return result;
    } catch (e) {
      debugPrint('WifiRssi.getRssi failed: $e');
      return null;
    }
  }
}
