package com.example.edge_sense

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val wifiChannelName = "com.edgesense.app/wifi"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wifiChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                // Returns current Wi-Fi RSSI in dBm, or null if unavailable (not connected,
                // permission not granted, or platform doesn't support it).
                "getRssi" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val rssi = wifiManager.connectionInfo?.rssi
                        if (rssi == null || rssi == -127) {
                            result.success(null)
                        } else {
                            result.success(rssi)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
