# Advanced Haptics

A Flutter plugin for playing powerful, custom haptic feedback patterns. This package provides a unified API for Android and iOS, giving developers access to fine-grained vibration control and Apple Core Haptics `.ahap` files.

[![pub version](https://img.shields.io/pub/v/advanced_haptics.svg)](https://pub.dev/packages/advanced_haptics)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/miracle101000/advanced_haptics/blob/main/LICENSE)

---

## ✨ Features

-   ✅ **Unified API**: A single, easy-to-use Dart API for both platforms.
-   🎯 **Custom Waveforms**: Full control of vibration timing, intensity, and looping.
-   🍎 **Core Haptics on iOS**: Play custom `.ahap` files and control the player state.
-   🧠 **Predefined Patterns**: A suite of built-in methods like `lightTap()`, `success()`, `error()` and more.
-   🧩 **Native Android Effects**: Access system-level vibration effects like `tick`, `heavyClick`, etc.
-   🛡️ **Capability Detection**: Easily check if a device supports advanced haptics.
-   🪶 **Graceful Fallbacks**: Sensible defaults for unsupported hardware or platforms.

---

## 🖥 Platform Support

| Feature             | Android (5.0+ / API 21+) | iOS (13.0+ / iPhone 8+) |
| ------------------- | ------------------------ | ----------------------- |
| Waveform            | ✅ API 26+ / 🔁 Fallback | ✅ Emulated             |
| `.ahap` Playback    | 🔁 Fallback              | ✅ Native               |
| Player Controls     | ❌ N/A                   | ✅ Native               |
| Amplitude Control   | ✅ API 26+               | ✅ Native               |
| Predefined Patterns | ✅ API 29+               | ✅ Native               |

> ℹ️ **Android note:** Amplitude control and waveform patterns require API 26 (Android 8.0 Oreo). On older devices, a simple fallback vibration is used. Predefined effects (e.g. `tick`, `click`) require API 29. Use `hasCustomHapticsSupport()` to check for full amplitude support at runtime.

> ℹ️ **Note:** iPads do not support Core Haptics. Always use `hasCustomHapticsSupport()` before playing advanced patterns to ensure a good user experience.

---

## 🚀 Getting Started

### 1. Install

Add `advanced_haptics` to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  advanced_haptics: ^1.0.7 # Use the latest version
```

Then, run `flutter pub get` in your terminal.

### 2. Android Setup

Add the `VIBRATE` permission to your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
    <!-- Add this line -->
    <uses-permission android:name="android.permission.VIBRATE"/>
    <application ...>
    </application>
</manifest>
```

### 3. iOS Setup

To play custom patterns on iOS, add your `.ahap` files to your project assets (e.g., under an `assets/haptics/` folder) and declare the folder in your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/haptics/
```

---

## 📦 Usage

Import the package in your Dart file:

```dart
import 'package:advanced_haptics/advanced_haptics.dart';
```

### General & Cross-Platform Methods

These methods are designed to work on both Android and iOS, with graceful fallbacks where necessary.

#### ✅ Capability Check

```dart
final bool hasSupport = await AdvancedHaptics.hasCustomHapticsSupport();
if (hasSupport) {
  // Safe to use advanced haptics
}
```

#### ⚡ Predefined Patterns

Use these for quick, consistent feedback across your app.

```dart
await AdvancedHaptics.lightTap();
await AdvancedHaptics.mediumTap();
await AdvancedHaptics.heavyRumble();
await AdvancedHaptics.success();
await AdvancedHaptics.error();
```

#### 🛑 Stop All Vibrations

Immediately cancels any ongoing haptic effect on either platform.

```dart
///atTime for iOS only
await AdvancedHaptics.stop(atTime: 0.0);
```

---

### Platform-Specific Features

These methods expose powerful, native-only features. Check for platform or use `hasCustomHapticsSupport()` before calling.

### 🤖 Android Specific

#### Custom Waveform (Android Preferred)

Design unique patterns with precise control over timings (in milliseconds), amplitudes (0-255), and an optional repeat index. While this is emulated on iOS, it provides the most granular control on Android.

```dart
// Plays a pattern, with no repeat
await AdvancedHaptics.playWaveform(
  [0, 100, 100, 200],     // Timings: [delay, on, off, on]
  [0, 180, 0, 255],       // Amplitudes for each segment
  repeat: -1              // -1 means no repeat
);
```

#### Native Android Effects (API 29+)

Play Android's built-in system haptic effects using an enum. This has no effect on iOS.

```dart
await AdvancedHaptics.playPredefined(AndroidPredefinedHaptic.tick);
```
*Available enums: `click`, `doubleClick`, `tick`, `heavyClick`, `pop`, `thud`, `ringtone1`.*

---

### 🍎 iOS Specific

#### Play `.ahap` File

Trigger your custom-designed haptic experiences on supported iPhones. This is the highest-fidelity way to play haptics on iOS.

```dart
await AdvancedHaptics.playAhap('assets/haptics/success.ahap');
```

#### Haptic Player Controls

These methods control the state of the active `CHHapticAdvancedPatternPlayer` on iOS, which is typically started by `playAhap` or `playWaveform`. **These have no effect on Android** — calling them on Android will return a not-implemented error, so guard with a platform check.

```dart
// Pause the currently playing haptic pattern
await AdvancedHaptics.pause(atTime: 0.0);

// Resume a paused pattern
await AdvancedHaptics.resume(atTime: 0.0);

// Jump to 0.5 seconds into the pattern
await AdvancedHaptics.seek(offset: 0.5);

// Cancel all scheduled events and stop immediately
await AdvancedHaptics.cancel();
```

---

## 🙌 Contributors

Thanks to these wonderful people for their contributions:

<table>
  <tr>
    <td align="center">
      <a href="https://github.com/miracle101000">
        <img src="https://github.com/miracle101000.png" width="80px;" alt="miracle101000"/><br/>
        <sub><b>miracle101000</b></sub>
      </a>
    </td>
    <td align="center">
      <a href="https://github.com/kvenn">
        <img src="https://github.com/kvenn.png" width="80px;" alt="kvenn"/><br/>
        <sub><b>kvenn</b></sub>
      </a>
    </td>
    <td align="center">
      <a href="https://github.com/rdeekshitha-scapia">
        <img src="https://github.com/rdeekshitha-scapia.png" width="80px;" alt="rdeekshitha-scapia"/><br/>
        <sub><b>rdeekshitha-scapia</b></sub>
      </a>
    </td>
    <td align="center">
      <a href="https://github.com/KoichiMatsudaMPL">
        <img src="https://github.com/KoichiMatsudaMPL.png" width="80px;" alt="KoichiMatsudaMPL"/><br/>
        <sub><b>KoichiMatsudaMPL</b></sub>
      </a>
    </td>
  </tr>
</table>

We welcome issues, feature requests, and pull requests! If submitting code, please test on both Android and iOS where applicable and provide details on the devices used.

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for full details.