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

## Edge Server Networks (Wi-Fi roaming across hotspots)

If your edge servers are each on their **own separate Wi-Fi hotspot** (different SSID per server), Android will **not** automatically switch between them as you walk from one server's coverage into another's — it only auto-roams within a set of networks it's been told are interchangeable (same SSID, or explicitly registered). Without that, the [multi-edge-server handover](../README.md#multi-edge-server-handover) never triggers, because it relies on the OS having already switched gateways.

To fix this, open **System Information → Edge Server Networks** in the app and add the Wi-Fi name + password of every edge-server hotspot. This registers them with Android via [`WifiNetworkSuggestion`](https://developer.android.com/reference/android/net/wifi/WifiNetworkSuggestion) (see [`hotspot_manager.dart`](lib/services/hotspot_manager.dart) and [`MainActivity.kt`](android/app/src/main/kotlin/com/example/edge_sense/MainActivity.kt)), which tells the OS these networks are all fair game for roaming — Android then switches between them on signal strength on its own, exactly like it would across APs on one enterprise Wi-Fi network. Requires Android 10+; the list is re-applied automatically on every app launch.

If Android still won't switch after registering the hotspots, check **Settings → Network & internet → Wi-Fi → Network suggestions → EdgeSense** — some devices require the user to explicitly approve an app's suggestions the first time.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
