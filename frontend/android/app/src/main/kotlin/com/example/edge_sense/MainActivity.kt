package com.example.edge_sense

import android.content.Context
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val wifiChannelName = "com.edgesense.app/wifi"

    // WifiNetworkSuggestion is API 29+; older devices get this sentinel instead of a
    // real status code so the Dart side can show an "unsupported" message.
    private val statusUnsupportedAndroidVersion = -100

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
                // Registers the full set of known edge-server hotspots with Android via
                // WifiNetworkSuggestion, so the OS can roam between them on signal strength
                // on its own — this is what actually fixes "Wi-Fi never switches" when each
                // edge server broadcasts its own distinct SSID. Replaces any suggestions this
                // app previously added. Argument: List<Map<String, String>> with "ssid" and
                // "password" (empty/absent password = open network). Returns the WifiManager
                // status code (0 = success), or -100 if unsupported on this Android version.
                "addWifiSuggestions" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.success(statusUnsupportedAndroidVersion)
                    } else {
                        try {
                            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            wifiManager.removeNetworkSuggestions(emptyList())

                            val rawList = call.arguments as? List<*> ?: emptyList<Any?>()
                            val suggestions = rawList.mapNotNull { raw ->
                                val entry = raw as? Map<*, *> ?: return@mapNotNull null
                                val ssid = entry["ssid"] as? String ?: return@mapNotNull null
                                val password = entry["password"] as? String ?: ""
                                val builder = WifiNetworkSuggestion.Builder().setSsid(ssid)
                                if (password.isNotEmpty()) {
                                    builder.setWpa2Passphrase(password)
                                }
                                builder.build()
                            }

                            val status = wifiManager.addNetworkSuggestions(suggestions)
                            result.success(status)
                        } catch (e: Exception) {
                            result.error("WIFI_SUGGESTION_ERROR", e.message, null)
                        }
                    }
                }
                // Removes all of this app's previously-added Wi-Fi network suggestions.
                "clearWifiSuggestions" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.success(statusUnsupportedAndroidVersion)
                    } else {
                        try {
                            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            val status = wifiManager.removeNetworkSuggestions(emptyList())
                            result.success(status)
                        } catch (e: Exception) {
                            result.error("WIFI_SUGGESTION_ERROR", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
