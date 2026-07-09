import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:edge_sense/models/edge_hotspot.dart';

/// Registers known edge-server Wi-Fi hotspots with Android via
/// WifiNetworkSuggestion, so the OS roams between them on signal strength on
/// its own. This exists because Android does *not* auto-switch between two
/// Wi-Fi networks with different SSIDs just because one gets stronger — it
/// only roams within a set of networks it's been told are interchangeable.
/// Without this, [HandoverController]'s session migration never triggers,
/// because it relies on Android already having switched gateways.
class HotspotManager {
  static const MethodChannel _channel = MethodChannel('com.edgesense.app/wifi');
  static const _prefsKey = 'edge_hotspots';

  static Future<List<EdgeHotspot>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => EdgeHotspot.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> _save(List<EdgeHotspot> hotspots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(hotspots.map((h) => h.toJson()).toList()));
  }

  /// Persists the given hotspot list and pushes it to Android. Returns a
  /// human-readable result to show the user.
  static Future<String> saveAndApply(List<EdgeHotspot> hotspots) async {
    await _save(hotspots);
    return applyToAndroid(hotspots);
  }

  /// Re-applies the currently saved hotspot list. Call this on app startup —
  /// Android doesn't remember an app's suggestions across a reinstall or
  /// "clear data", so they need to be re-registered each cold start.
  static Future<String> applySaved() async {
    final hotspots = await load();
    if (hotspots.isEmpty) return 'No edge-server hotspots configured yet.';
    return applyToAndroid(hotspots);
  }

  static Future<String> applyToAndroid(List<EdgeHotspot> hotspots) async {
    if (kIsWeb || !Platform.isAndroid) {
      return 'Wi-Fi network suggestions are only supported on Android.';
    }
    try {
      final status = await _channel.invokeMethod<int>(
        'addWifiSuggestions',
        hotspots.map((h) => h.toJson()).toList(),
      );
      return _describeStatus(status);
    } catch (e) {
      return 'Failed to register hotspots with Android: $e';
    }
  }

  static String _describeStatus(int? status) {
    switch (status) {
      case 0:
        return 'Registered with Android — it will roam between these networks automatically.';
      case -100:
        return 'Requires Android 10 or newer.';
      case 5:
        return 'Android is blocking suggestions from this app. Enable them under '
            'Settings → Network & internet → Wi-Fi → Network suggestions → EdgeSense.';
      default:
        return 'Android rejected the request (code $status). Double-check the SSID/password and try again.';
    }
  }
}
