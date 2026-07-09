import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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