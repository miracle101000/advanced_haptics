# Changelog

All notable changes to `advanced_haptics` will be documented in this file.

---

## 1.0.10

- **CHORE:** Bumped `flutter_lints` to `^6.0.0` (dev dependency only; no runtime changes). The package and example analyze cleanly under the current lint set.

---

## 1.0.9

Robustness release: every method is now safe to call on any platform and device.

- **FIX:** `AndroidPredefinedHaptic` used wrong effect IDs (`pop`/`thud`/`ringtone1` mapped to ringtone effects). IDs now match `android.os.VibrationEffect`; added `textureTick`. Unsupported effects fall back to `click` (API 30+).
- **FIX:** `cancel()`, `pause()`, `resume()` and `seek()` threw `MissingPluginException` on Android.
- **NEW:** `pause()`, `resume()` and `seek()` now work on Android. The vibrator has no native pause, so the plugin tracks the position inside the playing waveform, cancels on pause and replays the remainder (looping included) on resume or seek. `PLAYER_NIL` is thrown when nothing is playing, matching iOS.
- **FIX:** `stop()` and `cancel()` on iOS threw `PLAYER_NIL` when nothing was playing. They are now idempotent.
- **FIX:** `atTime` on iOS was passed as an absolute engine time, so scheduled playback/pause/resume/stop never worked. It is now a delay in seconds from now.
- **FIX:** iOS devices without Core Haptics (iPads, iPhone 7 and older) threw `UNSUPPORTED` on every call. They now fall back to `UIFeedbackGenerator`.
- **FIX:** iOS engine reset/stop handlers mutated state off the main thread, and a stale player could block new playback after an engine reset.
- **FIX:** Repeating waveforms on iOS ignored trailing silence (`loopEnd` was never set).
- **FIX:** Android crashed with `ClassCastException` when timings exceeded 32 bits, and `SecurityException` (missing `VIBRATE` permission) was not caught.
- **FIX:** `hasCustomHapticsSupport()` could throw on platforms without a native implementation or when the native side returned `null`.
- **NEW:** `playWaveform(repeat: ...)` is now a real parameter (it was documented but ignored).
- **NEW:** Dart-side argument validation with clear `ArgumentError`s (empty lists, mismatched lengths, negative timings, amplitudes outside 0-255, bad `repeat`, negative times).
- **NEW:** Android below API 26 plays the on/off shape of a waveform (previously a fixed 200 ms buzz); `playPredefined` plays an approximation below API 29 instead of erroring. Uses `VibratorManager` on API 31+.
- **NEW:** Very short iOS waveform segments (< 40 ms) are rendered as transient taps, which are far more perceptible.
- **NEW:** `playAhap` accepts absolute file paths in addition to Flutter asset paths.
- **NEW:** `AdvancedHapticsPlatform` is now a real platform interface: replace `AdvancedHapticsPlatform.instance` with a mock in tests.
- **NEW:** iOS sources ship as a Swift package (`ios/advanced_haptics/Package.swift`) with a privacy manifest, so apps built with Swift Package Manager (default since Flutter 3.44) no longer fall back to CocoaPods. The podspec is kept for CocoaPods users.
- **CHORE:** Real Dart and Kotlin unit tests; podspec metadata; plugin `build.gradle` moved to Java 17 / `compileSdk 36` and no longer double-applies the Kotlin plugin under AGP 9.
- **CHORE:** Example app modernised: Gradle 9.1 / AGP 9.0.1 / Kotlin 2.3.20 (it could not build on the JDK current Flutter uses), iOS deployment target 13.0 (the podspec minimum), error reporting in the UI, demos for looping waveforms, predefined effects and player controls.

---

## 1.0.8
Updated ReadMe


---

## 1.0.7
**Contributor:** [@rdeekshitha-scapia](https://github.com/rdeekshitha-scapia) — [#4](https://github.com/miracle101000/advanced_haptics/pull/4)

- **FIX:** Lowered `minSdkVersion` from 26 to 21, allowing the plugin to be used in apps targeting Android 5.0+. API 26 (Oreo) haptic requirements are now enforced at runtime via a centralized `hasOreoHaptics()` check rather than at the build level.

---

## 1.0.6
**Contributor:** [@kvenn](https://github.com/kvenn) — `kvenn/bug-foreground-restart`

- **FIX:** Resolved an issue where `lightTap()` and `mediumTap()` were not triggering haptic feedback on iOS (e.g. iPhone 13 Pro, iOS 18), while `success()` worked correctly. Reported in [#2](https://github.com/miracle101000/advanced_haptics/issues/2).

---

## 1.0.5

- **FIX:** Resolved a build error on iOS versions below 16 caused by use of `CHHapticPattern(contentsOf:)`, which is only available in iOS 16+. Implemented a fallback using manual AHAP JSON decoding and `CHHapticPattern(dictionary:)` for compatibility with iOS 13–15.

---

## 1.0.4

- Updated README.

---

## 1.0.3

- Added platform-specific methods for iOS.
- Improved README structure and organization.

---

## 1.0.2

- Added platform-specific methods for Android.

---

## 1.0.1

- Updated README.

---

## 1.0.0

- Proper launch of `advanced_haptics`.

---

## 0.0.6

- **FIX:** Resolved a build error on iOS (`Cannot find type 'CHHapticPlayer' in scope`) by adding the necessary `CoreHaptics` framework import.

---

## 0.0.5

- Fixed playback issues on iOS in the `waveform` method.

---

## 0.0.4

- Fixed playback issues on iOS in the `waveform` method.

---

## 0.0.3

- Fixed bug in iOS.

---

## 0.0.2

- Updated README.

---

## 0.0.1

- Initial release of the `advanced_haptics` package.
- Support for Android waveform patterns.
- Support for iOS Core Haptics via `.ahap` files.
- Added predefined patterns and device support checking.