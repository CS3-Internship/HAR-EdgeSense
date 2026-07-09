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

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
