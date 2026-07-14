# edge_sense

The EdgeSense mobile app — see the [top-level README](../README.md) for what the project does end to end.

## Downloading a build

Pushing a version tag builds a release APK and attaches it to a GitHub Release automatically:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Watch progress under the repo's **Actions** tab; once it finishes, the APK is downloadable from the **Releases** page. You can also trigger a build without tagging via **Actions → Build & Release Android APK → Run workflow**.

> **Signing note**: this APK is currently signed with the Flutter debug key (`android/app/build.gradle.kts` → `signingConfig = signingConfigs.getByName("debug")`), which installs and runs fine for direct/sideloaded downloads. It is **not** suitable for the Play Store, and if you ever switch to a real release keystore, every device that installed a debug-signed build will need to uninstall first — Android refuses to install an update signed with a different key over an existing install.

## Edge Server Networks (Wi-Fi switching across hotspots)

If your edge servers are each on their **own separate Wi-Fi hotspot** (different SSID per server, e.g. each phone's personal hotspot), two problems show up without help from the app:

1. **Android won't switch Wi-Fi networks on its own.** It only auto-roams within a set of networks it's been told are interchangeable (same SSID, or explicitly registered) — it will not abandon a hotspot that's still functioning, even weakly, in favor of a different one, no matter how close you get to it.
2. **Even a manual Wi-Fi switch may not trigger migration**, because phone personal hotspots commonly all default their gateway IP to the same address (e.g. `192.168.43.1`). If the app derives each edge server's URL from that gateway IP, two different physical servers end up with the *identical* address — so the app can't tell anything changed, and the [multi-edge-server handover](../README.md#multi-edge-server-handover) silently never runs.

Both are fixed via **System Information → Edge Server Networks**, where you register each hotspot's Wi-Fi name, password, and **explicit edge server address** (e.g. `http://192.168.43.1:5000`):

* **Addressing** ([`edge_hotspot.dart`](lib/models/edge_hotspot.dart)): the server URL you enter is used directly, keyed by SSID — never guessed from gateway IP. This alone fixes problem #2, regardless of how the Wi-Fi switch happens.
* **Switching** ([`wifi_connector.dart`](lib/services/wifi_connector.dart), [`handover_controller.dart`](lib/services/handover_controller.dart), [`MainActivity.kt`](android/app/src/main/kotlin/com/example/edge_sense/MainActivity.kt)): once the fuzzy urgency score is elevated, the app scans for other registered hotspots in range and actively forces a connection to the best one via Android's [`WifiNetworkSpecifier`](https://developer.android.com/reference/android/net/wifi/WifiNetworkSpecifier) API, then binds the app's traffic to it — rather than passively hoping Android switches on its own. The first connection to a given SSID shows a one-time system "Allow this app to connect?" dialog; Android remembers the choice afterward. Requires Android 10+.

The app also registers all hotspots via [`WifiNetworkSuggestion`](https://developer.android.com/reference/android/net/wifi/WifiNetworkSuggestion) as a harmless best-effort background hint (re-applied on every launch), but that API alone is **not** sufficient — see problem #1 above — which is why the active `WifiNetworkSpecifier` path exists.

### Testing: manual "Migrate Now"

**System Information → Migration (Testing)** has a button that triggers a migration attempt immediately — it re-resolves whatever edge server the phone is actually on right now (fresh SSID/gateway lookup) and, if that differs from the server the app currently thinks it's using, runs the full snapshot + database migration and purge right away. Useful for testing the migration pipeline itself without waiting on the fuzzy urgency score to rise or a scan cycle to run. The server left behind by the most recent migration is also shown as "Previous Edge Server" in the network info card for visibility while testing.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
