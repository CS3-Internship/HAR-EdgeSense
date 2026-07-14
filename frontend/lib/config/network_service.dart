import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:edge_sense/services/hotspot_manager.dart';
import 'network_config.dart';

Future<void> initializeNetwork() async {
  if (kIsWeb) {
    debugPrint("Running on Web");
    return;
  }

  try {
    debugPrint("=== initializeNetwork() ===");

    final status = await Permission.locationWhenInUse.request();
    debugPrint("Permission: $status");

    final info = NetworkInfo();

    // Prefer a registered hotspot's explicit server URL (keyed by SSID) over
    // guessing from the gateway IP — phone personal hotspots commonly all
    // default to the same gateway address regardless of which phone is
    // hosting them, so the guess can silently point at the wrong server.
    final hotspots = await HotspotManager.load();
    String? ssid;
    try {
      ssid = await info.getWifiName();
    } catch (e) {
      debugPrint("SSID lookup failed: $e");
    }
    final match = HotspotManager.findBySsid(hotspots, ssid);
    if (match != null) {
      serverBaseUrl = match.serverUrl;
      debugPrint("Server Base URL (from registered hotspot '$ssid') = $serverBaseUrl");
      return;
    }

    final gateway = await info.getWifiGatewayIP();
    debugPrint("Gateway: $gateway");

    if (gateway == null || gateway.isEmpty) {
      throw Exception("Gateway IP not found");
    }

    serverBaseUrl = "http://$gateway:5000";

    debugPrint("Server Base URL = $serverBaseUrl");
  } catch (e) {
    debugPrint("initializeNetwork FAILED: $e");
  }
}