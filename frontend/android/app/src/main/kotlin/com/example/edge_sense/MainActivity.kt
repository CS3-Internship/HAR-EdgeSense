package com.example.edge_sense

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val wifiChannelName = "com.edgesense.app/wifi"

    // WifiNetworkSuggestion/WifiNetworkSpecifier are API 29+; older devices get this
    // sentinel instead of a real status code so the Dart side can show an "unsupported" message.
    private val statusUnsupportedAndroidVersion = -100

    // Tracks the in-flight connection request so a new one can replace it cleanly
    // instead of leaking callbacks each time the app switches edge servers.
    private var activeNetworkCallback: ConnectivityManager.NetworkCallback? = null

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
                // Actively requests a connection to a specific SSID via WifiNetworkSpecifier and
                // binds this app's traffic to it once connected. Unlike WifiNetworkSuggestion
                // (which only helps Android auto-connect when it has no working Wi-Fi at all),
                // this forces the switch even while already connected to a different, still-
                // functioning network — which is what a hotspot-to-hotspot handover needs.
                // The first connection to a given SSID shows a one-time system "Allow this app
                // to connect?" dialog; Android remembers the choice afterward.
                // Argument: {"ssid": String, "password": String}. Returns 0 on success, 1 if the
                // request timed out/failed, or -100 if unsupported on this Android version.
                "connectToWifi" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.success(statusUnsupportedAndroidVersion)
                    } else {
                        try {
                            val args = call.arguments as? Map<*, *>
                            val ssid = args?.get("ssid") as? String
                            val password = args?.get("password") as? String ?: ""
                            if (ssid.isNullOrEmpty()) {
                                result.error("INVALID_ARGS", "ssid is required", null)
                            } else {
                                val connectivityManager =
                                    applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

                                activeNetworkCallback?.let {
                                    try {
                                        connectivityManager.unregisterNetworkCallback(it)
                                    } catch (e: Exception) {
                                        // Already unregistered/expired — safe to ignore.
                                    }
                                }

                                val specifierBuilder = WifiNetworkSpecifier.Builder().setSsid(ssid)
                                if (password.isNotEmpty()) {
                                    specifierBuilder.setWpa2Passphrase(password)
                                }

                                val request = NetworkRequest.Builder()
                                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                                    .setNetworkSpecifier(specifierBuilder.build())
                                    .build()

                                var resultDelivered = false
                                val callback = object : ConnectivityManager.NetworkCallback() {
                                    override fun onAvailable(network: Network) {
                                        super.onAvailable(network)
                                        connectivityManager.bindProcessToNetwork(network)
                                        if (!resultDelivered) {
                                            resultDelivered = true
                                            result.success(0)
                                        }
                                    }

                                    override fun onUnavailable() {
                                        super.onUnavailable()
                                        if (!resultDelivered) {
                                            resultDelivered = true
                                            result.success(1)
                                        }
                                    }
                                }
                                activeNetworkCallback = callback
                                connectivityManager.requestNetwork(request, callback, 30000)
                            }
                        } catch (e: Exception) {
                            result.error("WIFI_CONNECT_ERROR", e.message, null)
                        }
                    }
                }
                // Triggers a Wi-Fi scan and returns currently-visible networks as
                // List<Map<String, Any>> with "ssid" and "rssi" keys. startScan() is
                // throttled by the OS for non-system apps, so results may reflect the
                // system's own recent ambient scan rather than one triggered right now.
                "scanWifi" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        @Suppress("DEPRECATION")
                        wifiManager.startScan()
                        val scanResults = wifiManager.scanResults.map { r ->
                            mapOf("ssid" to r.SSID, "rssi" to r.level)
                        }
                        result.success(scanResults)
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, Any>>())
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
