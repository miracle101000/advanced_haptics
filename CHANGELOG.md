## 0.0.1

- Initial release of the `advanced_haptics` package.
- Support for Android waveform patterns.
- Support for iOS Core Haptics via `.ahap` files.
- Added predefined patterns and device support checking.

## 0.0.2

- Updated ReadMe

## 0.0.3

- Updated Fixed bug in iOS

## 0.0.4

- Updated Fixing play back issues on ios in waveform method

## 0.0.5

- Updated Fixing play back issues on ios in waveform method

## 0.0.6

- **FIX:** Resolved a build error on iOS (`Cannot find type 'CHHapticPlayer' in scope`) by adding the necessary `CoreHaptics` framework import.

## 1.0.0

- Proper launch

## 1.0.1

- Updated ReadMe


## 1.0.2

- Platform specific methods Android

## 1.0.3

- Platform specific methods iOS and better organized readme


## 1.0.4

- Updated ReadMe


## 1.0.5

- Resolved a build error on iOS versions below 16 caused by use of CHHapticPattern(contentsOf:), which is only available in iOS 16+. Implemented a fallback using manual AHAP JSON decoding and CHHapticPattern(dictionary:) for compatibility with iOS 13–15.

## 1.0.6
from kvenn/bug-foreground-restart (Fixed)