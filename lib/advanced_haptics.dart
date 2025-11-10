import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents Android's predefined vibration effects (API 29+).
enum AndroidPredefinedHaptic {
  click(0),
  doubleClick(1),
  tick(2),
  heavyClick(5),
  pop(6),
  thud(7),
  ringtone1(8);

  const AndroidPredefinedHaptic(this.effectId);
  final int effectId;
}

/// A Flutter plugin for playing powerful, custom haptic feedback patterns.
///
/// This class provides a unified API to access Android's `VibrationEffect.createWaveform`
/// and iOS's Core Haptics, enabling fine-grained control over tactile feedback.
class AdvancedHaptics {
  static const MethodChannel _channel =
      MethodChannel('com.example/advanced_haptics');

  /// Checks if the device supports custom haptics.
  ///
  /// On iOS, this checks for Core Haptics support (iPhone 8+).
  /// On Android, this checks if the vibrator can control amplitude.
  static Future<bool> hasCustomHapticsSupport() async {
    try {
      final bool hasSupport =
          await _channel.invokeMethod('hasCustomHapticsSupport');
      return hasSupport;
    } on PlatformException {
      return false;
    }
  }

  /// Plays a haptic pattern defined by timings and amplitudes.
  ///
  /// [timings] - A list of integers representing the duration of each vibration and pause in milliseconds.
  ///             e.g., `[off, on, off, on, ...]`. The first value is the initial delay.
  /// [amplitudes] - A list of integers (0-255) for the intensity of each vibration.
  ///                The length must be the same as [timings]. Use 0 for pauses.
  ///
  /// This maps directly to Android's `VibrationEffect.createWaveform`.
  /// On iOS, this is emulated with a series of transient haptics and is less precise.
  /// The `atTime` parameter is primarily for iOS scheduling.
  static Future<void> playWaveform(
    List<int> timings,
    List<int> amplitudes, {
    double atTime = 0.0,
  }) async {
    if (timings.length != amplitudes.length) {
      throw ArgumentError(
          'Timings and amplitudes lists must have the same length.');
    }
    await _channel.invokeMethod('playWaveform', {
      'timings': timings,
      'amplitudes': amplitudes,
      'atTime': atTime,
    });
  }

  /// Plays a custom haptic pattern from an .ahap file on iOS.
  ///
  /// [ahapPath] - The asset path to the .ahap file (e.g., 'assets/haptics/rumble.ahap').
  /// The `atTime` parameter allows for scheduled playback.
  ///
  /// On Android, this falls back to a predefined, strong vibration pattern.
  static Future<void> playAhap(String ahapPath, {double atTime = 0.0}) async {
    await _channel.invokeMethod('playAhap', {
      'path': ahapPath,
      'atTime': atTime,
    });
  }

  // --------------------------------------------
  // 🔽 NEW! Player Control Methods (iOS-focused)
  // --------------------------------------------

  /// Pauses the currently active haptic player.
  ///
  /// **Platform Specific:** This primarily affects the `CHHapticAdvancedPatternPlayer` on iOS
  /// that was started by `playWaveform` or `playAhap`. It has no effect on Android.
  ///
  /// [atTime] - The time, in seconds, to schedule the pause. Use `0.0` for immediate.
  static Future<void> pause({double atTime = 0.0}) async {
    await _channel.invokeMethod('pause', {'atTime': atTime});
  }

  /// Resumes a paused haptic player.
  ///
  /// **Platform Specific:** This is for resuming a player on iOS that was previously paused.
  /// It has no effect on Android.
  ///
  /// [atTime] - The time, in seconds, to schedule the resumption. Use `0.0` for immediate.
  static Future<void> resume({double atTime = 0.0}) async {
    await _channel.invokeMethod('resume', {'atTime': atTime});
  }

  /// Seeks to a specific point in the active haptic pattern.
  ///
  /// **Platform Specific:** This is for seeking within a playing pattern on iOS.
  /// It has no effect on Android.
  ///
  /// [offset] - The time, in seconds, to seek to within the pattern.
  static Future<void> seek({required double offset}) async {
    await _channel.invokeMethod('seek', {'offset': offset});
  }

  /// Stops any currently playing haptic pattern.
  ///
  /// On iOS, this stops the active `CHHapticAdvancedPatternPlayer`.
  /// On Android, this cancels the `Vibrator`.
  ///
  /// [atTime] - (iOS only) The time, in seconds, to schedule the stop. Use `0.0` for immediate.
  static Future<void> stop({double atTime = 0.0}) async {
    await _channel.invokeMethod('stop', {'atTime': atTime});
  }

  /// Cancels the haptic player immediately, ignoring any scheduled events.
  ///
  /// **Platform Specific:** This is for cancelling a player on iOS.
  /// On Android, this method currently has no effect beyond what `stop()` does.
  static Future<void> cancel() async {
    await _channel.invokeMethod('cancel');
  }

  // --------------------------------------------
  // 🔽 Utility Presets
  // --------------------------------------------

  /// Plays a simple, predefined "success" haptic.
  static Future<void> success() async {
    await _channel.invokeMethod('success');
  }

  /// Plays a quick, light tap haptic feedback.
  static Future<void> lightTap({
    List<int> timings = const [0, 30],
    List<int> amplitudes = const [0, 180],
  }) async {
    await playWaveform(timings, amplitudes);
  }

  /// Plays a medium-strength haptic tap.
  static Future<void> mediumTap({
    List<int> timings = const [0, 50],
    List<int> amplitudes = const [0, 220],
  }) async {
    await playWaveform(timings, amplitudes);
  }

  /// Plays a strong, short "heavy rumble" haptic.
  static Future<void> heavyRumble({
    List<int> timings = const [0, 200],
    List<int> amplitudes = const [0, 255],
  }) async {
    await playWaveform(timings, amplitudes);
  }

  /// Plays a double-tap success haptic pattern.
  static Future<void> successBuzz({
    List<int> timings = const [0, 50, 100, 50],
    List<int> amplitudes = const [0, 255, 0, 255],
  }) async {
    await playWaveform(timings, amplitudes);
  }

  /// Plays an error-like feedback with two longer buzzes.
  static Future<void> error({
    List<int> timings = const [0, 100, 50, 100],
    List<int> amplitudes = const [0, 255, 0, 200],
  }) async {
    await playWaveform(timings, amplitudes);
  }

  /// Plays a short, crisp selection click haptic.
  static Future<void> selectionClick({
    List<int> timings = const [0, 20],
    List<int> amplitudes = const [0, 120],
  }) async {
    await playWaveform(timings, amplitudes);
  }

  /// Plays a predefined haptic pattern on Android (API 29+).
  /// Ignored on iOS.
  static Future<void> playPredefined(AndroidPredefinedHaptic effect) async {
    // We can add a platform check to avoid an unnecessary method call
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod('playPredefined', {
        'effectId': effect.effectId,
      });
    }
  }
}
