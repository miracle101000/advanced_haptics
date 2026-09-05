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

| Feature             | Android (5.0+ / API 21+) | iOS (13.0+)                       |
| ------------------- | ------------------------ | --------------------------------- |
| Waveform            | ✅ API 26+ / 🔁 Fallback | ✅ Emulated (iPhone 8+) / 🔁 Fallback |
| `.ahap` Playback    | 🔁 Fallback              | ✅ Native (iPhone 8+) / 🔁 Fallback   |
| Player Controls     | ✅ Emulated              | ✅ Native                         |
| Amplitude Control   | ✅ API 26+               | ✅ Native (iPhone 8+)             |
| Predefined Patterns | ✅ API 29+ / 🔁 Fallback | ➖ Ignored                        |

> ℹ️ **Android note:** Amplitude control requires API 26 (Android 8.0 Oreo). On older devices the on/off shape of the pattern is played through the legacy vibrator API. Predefined effects (e.g. `tick`, `click`) require API 29; older devices play a short approximation. Use `hasCustomHapticsSupport()` to check for full amplitude support at runtime.

> ℹ️ **iOS note:** iPads and iPhones older than the iPhone 8 do not support Core Haptics. On those devices the plugin falls back to `UIFeedbackGenerator` taps, and the player controls do nothing. Use `hasCustomHapticsSupport()` when you need to know whether the full pattern will be played.

> 🛡️ **Safety:** Every method can be called on any platform. Web and desktop (no native implementation), devices without a vibrator, and unsupported hardware silently do nothing. Invalid arguments throw an `ArgumentError`; native failures surface as a `PlatformException` (see [Error codes](#-error-codes)).

---

## 🚀 Getting Started

### 1. Install

Add `advanced_haptics` to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  advanced_haptics: ^1.0.10 # Use the latest version
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

The plugin requires iOS 13.0 or newer (`platform :ios, '13.0'` in your `Podfile` / the Runner deployment target). It ships both a Swift package (used automatically when Swift Package Manager is enabled, the default since Flutter 3.44) and a podspec for CocoaPods; no configuration is needed for either.

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

Cancels any ongoing haptic effect on either platform. Safe to call when nothing is playing.

```dart
// atTime (iOS only): delay in seconds before stopping. 0.0 stops immediately.
await AdvancedHaptics.stop(atTime: 0.0);
```

---

### Platform-Specific Features

These methods expose powerful, native-only features. Check for platform or use `hasCustomHapticsSupport()` before calling.

### 🤖 Android Specific

#### Custom Waveform (Android Preferred)

Design unique patterns with precise control over timings (in milliseconds), amplitudes (0-255), and an optional repeat index. While this is emulated on iOS, it provides the most granular control on Android.

```dart
// Plays a pattern once
await AdvancedHaptics.playWaveform(
  [0, 100, 100, 200],     // Timings: [delay, on, off, on]
  [0, 180, 0, 255],       // Amplitudes for each segment
  repeat: -1,             // -1 (default) means no repeat
);

// Loops from index 2 until stop() is called
await AdvancedHaptics.playWaveform(
  [0, 500, 100, 50],
  [0, 255, 0, 120],
  repeat: 2,
);
await Future.delayed(const Duration(seconds: 3));
await AdvancedHaptics.stop();
```

Both lists must be non-empty and of equal length, timings must be non-negative, amplitudes must be within 0-255, and `repeat` must be `-1` or a valid index; otherwise an `ArgumentError` is thrown before anything reaches the platform.

> On iOS the whole pattern loops when `repeat` is not `-1` (Core Haptics has no loop start point). Segments shorter than 40 ms are rendered as crisp transient taps.

#### Native Android Effects (API 29+)

Play Android's built-in system haptic effects using an enum. This has no effect on iOS.

```dart
await AdvancedHaptics.playPredefined(AndroidPredefinedHaptic.tick);
```
*Available enums: `click`, `doubleClick`, `tick`, `heavyClick` (public, always available on API 29+) and `thud`, `pop`, `ringtone1`, `textureTick` (non-public effect IDs whose support varies by device; unsupported ones fall back to `click` on API 30+).*

---

#### Haptic Player Controls

Pause, resume and seek the pattern started by `playWaveform`, `playAhap` or `success`. On iOS these drive the `CHHapticAdvancedPatternPlayer`. Android has no native pause, so the plugin remembers where the waveform is, cancels the vibrator on pause, and replays the remainder (including the `repeat` loop) on resume or seek. Predefined Android effects cannot be paused. On iOS devices without Core Haptics the controls do nothing.

`pause`, `resume` and `seek` throw a `PlatformException` with code `PLAYER_NIL` when no pattern is playing or paused; `stop` and `cancel` never do. All `atTime` values are delays in seconds from now.

```dart
await AdvancedHaptics.playWaveform([0, 400, 150, 40], [0, 255, 0, 160], repeat: 2);

// Pause the currently playing haptic pattern
await AdvancedHaptics.pause();

// Resume where it left off
await AdvancedHaptics.resume();

// Jump to 0.5 seconds into the pattern
await AdvancedHaptics.seek(offset: 0.5);

// Cancel all scheduled events and stop immediately
await AdvancedHaptics.cancel();
```

---

### 🍎 iOS Specific

#### Play `.ahap` File

Trigger your custom-designed haptic experiences on supported iPhones. This is the highest-fidelity way to play haptics on iOS. The path is a Flutter asset path declared in `pubspec.yaml`, or an absolute file-system path (e.g. a downloaded file).

```dart
await AdvancedHaptics.playAhap('assets/haptics/success.ahap');

// Start playback 0.5 seconds from now
await AdvancedHaptics.playAhap('assets/haptics/success.ahap', atTime: 0.5);
```

---

### ⚠️ Error codes

Native failures are reported as a `PlatformException` with one of these codes:

| Code                   | Platform | Meaning                                                                 |
| ---------------------- | -------- | ----------------------------------------------------------------------- |
| `INVALID_ARGS`         | both     | Arguments rejected by the native side.                                  |
| `PERMISSION_DENIED`    | Android  | `android.permission.VIBRATE` is missing from the manifest.              |
| `VIBRATION_ERROR`      | Android  | The vibrator service failed.                                            |
| `ENGINE_NIL`           | iOS      | The Core Haptics engine could not be created.                           |
| `ENGINE_START_FAILED`  | iOS      | The engine could not be (re)started, e.g. while the app is in the background. |
| `PATTERN_ERROR`        | iOS      | The waveform or `.ahap` file could not be turned into a pattern.        |
| `FILE_NOT_FOUND`       | iOS      | The `.ahap` asset does not exist.                                       |
| `PLAYBACK_ERROR`       | iOS      | The player could not be started.                                        |
| `PLAYER_NIL`           | both     | `pause`/`resume`/`seek` called with no pattern playing or paused.       |
| `PLAYER_CONTROL_ERROR` | iOS      | `pause`/`resume`/`seek` failed.                                         |

---

### 🧪 Testing

`AdvancedHaptics` delegates to `AdvancedHapticsPlatform.instance`, so tests can swap in a fake to record or silence haptic calls:

```dart
import 'package:advanced_haptics/advanced_haptics.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeHaptics extends AdvancedHapticsPlatform with MockPlatformInterfaceMixin {
  final calls = <String>[];

  @override
  Future<bool> hasCustomHapticsSupport() async => true;

  @override
  Future<void> playWaveform({
    required List<int> timings,
    required List<int> amplitudes,
    int repeat = -1,
    double atTime = 0.0,
  }) async => calls.add('playWaveform');
  // Override the other methods you care about; the defaults throw UnimplementedError.
}

void main() {
  setUp(() => AdvancedHapticsPlatform.instance = FakeHaptics());
}
```

Without a fake, the plugin is still safe in `flutter test`: with no native implementation every call is a no-op and `hasCustomHapticsSupport()` returns `false`.

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