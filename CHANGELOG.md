# Changelog

All notable changes to `advanced_haptics` will be documented in this file.

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