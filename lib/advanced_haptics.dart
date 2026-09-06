import 'package:flutter/foundation.dart';

import 'advanced_haptics_platform_interface.dart';
import 'src/android_primitives.dart';
import 'src/haptic_pattern.dart';

export 'advanced_haptics_platform_interface.dart' show AdvancedHapticsPlatform;
export 'src/android_primitives.dart';
export 'src/haptic_pattern.dart';

/// Android's predefined vibration effects (`VibrationEffect.createPredefined`,
/// API 29+).
///
/// The numeric values are the effect IDs from `android.os.VibrationEffect`.
/// [click], [doubleClick], [tick] and [heavyClick] are public, guaranteed
/// effects. [thud], [pop], [ringtone1] and [textureTick] are non-public
/// effect IDs whose availability depends on the device; when the device
/// reports that one of them is unsupported (API 30+), the plugin falls back to
/// [click].
enum AndroidPredefinedHaptic {
  /// `VibrationEffect.EFFECT_CLICK`
  click(0),

  /// `VibrationEffect.EFFECT_DOUBLE_CLICK`
  doubleClick(1),

  /// `VibrationEffect.EFFECT_TICK`
  tick(2),

  /// `VibrationEffect.EFFECT_THUD` (non-public effect, device dependent)
  thud(3),

  /// `VibrationEffect.EFFECT_POP` (non-public effect, device dependent)
  pop(4),

  /// `VibrationEffect.EFFECT_HEAVY_CLICK`
  heavyClick(5),

  /// The first ringtone effect (non-public effect, device dependent)
  ringtone1(6),

  /// `VibrationEffect.EFFECT_TEXTURE_TICK` (non-public effect, device
  /// dependent)
  textureTick(21);

  const AndroidPredefinedHaptic(this.effectId);

  /// The raw Android effect ID.
  final int effectId;
}

/// A Flutter plugin for playing powerful, custom haptic feedback patterns.
///
/// This class provides a unified API to access Android's
/// `VibrationEffect.createWaveform` and iOS's Core Haptics, enabling
/// fine-grained control over tactile feedback.
///
/// Every method is safe to call on any platform: platforms without a native
/// implementation (web, desktop) and hardware without haptics silently do
/// nothing. Invalid arguments throw an [ArgumentError]; native failures
/// surface as a `PlatformException`.
class AdvancedHaptics {
  AdvancedHaptics._();

  /// The maximum amplitude accepted by [playWaveform].
  static const int maxAmplitude = 255;

  static AdvancedHapticsPlatform get _platform =>
      AdvancedHapticsPlatform.instance;

  /// Checks if the device supports custom haptics.
  ///
  /// On iOS, this checks for Core Haptics support (iPhone 8 and newer).
  /// On Android, this checks that a vibrator exists and can control amplitude
  /// (API 26+).
  ///
  /// Never throws: returns `false` when support cannot be determined.
  static Future<bool> hasCustomHapticsSupport() async {
    try {
      return await _platform.hasCustomHapticsSupport();
    } catch (_) {
      return false;
    }
  }

  /// Plays a haptic pattern defined by timings and amplitudes.
  ///
  /// [timings] - Duration of each segment in milliseconds, e.g.
  /// `[off, on, off, on, ...]`. The first value is the initial delay.
  /// [amplitudes] - Intensity (0-255) of each segment. Must be the same
  /// length as [timings]. Use 0 for pauses.
  /// [repeat] - Index into [timings] at which to restart the pattern after it
  /// finishes, or `-1` (the default) to play it once. A repeating pattern
  /// plays until [stop] or [cancel] is called. On iOS the whole pattern loops.
  /// [atTime] - (iOS only) Delay in seconds before playback starts. Use `0.0`
  /// for immediate playback.
  ///
  /// This maps directly to Android's `VibrationEffect.createWaveform`. On
  /// Android devices below API 26 the on/off pattern is played without
  /// amplitude control. On iOS the pattern is emulated with Core Haptics
  /// events and is less precise; on iOS devices without Core Haptics a
  /// `UIImpactFeedbackGenerator` fallback is used.
  ///
  /// Throws an [ArgumentError] when the lists are empty, differ in length,
  /// contain negative timings or out-of-range amplitudes, or when [repeat] is
  /// not `-1` and not a valid index.
  static Future<void> playWaveform(
    List<int> timings,
    List<int> amplitudes, {
    int repeat = -1,
    double atTime = 0.0,
  }) async {
    _validateWaveform(timings, amplitudes, repeat);
    _validateTime(atTime, 'atTime');
    await _platform.playWaveform(
      timings: List<int>.unmodifiable(timings),
      amplitudes: List<int>.unmodifiable(amplitudes),
      repeat: repeat,
      atTime: atTime,
    );
  }

  /// Plays a platform-independent [HapticPattern].
  ///
  /// This is the recommended way to design one pattern for both platforms.
  /// Build it with [HapticPatternBuilder] or from [HapticEvent]s directly.
  ///
  /// Rendering:
  /// * **iOS** (Core Haptics): every [HapticTransient] and [HapticContinuous]
  ///   becomes the matching Core Haptics event with its intensity and
  ///   sharpness.
  /// * **Android 11+** with primitive support: a pattern made only of
  ///   transients is played as a `VibrationEffect.Composition` (`TICK`,
  ///   `CLICK` or `THUD` chosen by sharpness).
  /// * **Everywhere else**: the pattern is flattened with
  ///   [HapticPattern.toWaveform] and played like [playWaveform].
  ///
  /// [atTime] - (iOS only) Delay in seconds before playback starts.
  ///
  /// An empty pattern does nothing. Throws an [ArgumentError] when any event
  /// is out of range.
  static Future<void> playPattern(
    HapticPattern pattern, {
    double atTime = 0.0,
  }) async {
    pattern.validate();
    _validateTime(atTime, 'atTime');
    if (pattern.isEmpty) {
      return;
    }
    final waveform = pattern.toWaveform();
    await _platform.playPattern(
      events: pattern.toJson(),
      timings: waveform.timings,
      amplitudes: waveform.amplitudes,
      atTime: atTime,
    );
  }

  /// Plays an Android `VibrationEffect.Composition` built from [primitives].
  ///
  /// On Android 11+ (API 30) with hardware support the primitives play
  /// natively; on older or unsupported Android devices a waveform
  /// approximation is played instead. On iOS the composition is rendered
  /// through [playPattern] using the closest Core Haptics events, so the same
  /// call gives sensible feedback on both platforms.
  ///
  /// Throws an [ArgumentError] when [primitives] is empty or a scale or delay
  /// is out of range.
  static Future<void> playComposition(
    List<AndroidPrimitiveEvent> primitives,
  ) async {
    if (primitives.isEmpty) {
      throw ArgumentError.value(primitives, 'primitives', 'must not be empty');
    }
    for (final p in primitives) {
      p.validate();
    }
    final pattern = AndroidPrimitiveEvent.toPattern(primitives);
    final waveform = pattern.toWaveform();
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _platform.playComposition(
        primitives: [for (final p in primitives) p.toJson()],
        timings: waveform.timings,
        amplitudes: waveform.amplitudes,
      );
    } else {
      await _platform.playPattern(
        events: pattern.toJson(),
        timings: waveform.timings,
        amplitudes: waveform.amplitudes,
      );
    }
  }

  /// Whether this Android device can play every primitive in [primitives]
  /// natively (API 30+ and hardware support).
  ///
  /// Defaults to checking [AndroidHapticPrimitive.click] and
  /// [AndroidHapticPrimitive.tick], the two [playPattern] relies on. Always
  /// `false` on other platforms, and never throws.
  static Future<bool> supportsAndroidPrimitives([
    List<AndroidHapticPrimitive> primitives = const [
      AndroidHapticPrimitive.click,
      AndroidHapticPrimitive.tick,
    ],
  ]) async {
    if (defaultTargetPlatform != TargetPlatform.android || primitives.isEmpty) {
      return false;
    }
    try {
      return await _platform.arePrimitivesSupported(
        ids: [for (final p in primitives) p.id],
      );
    } catch (_) {
      return false;
    }
  }

  /// Plays a custom haptic pattern from an `.ahap` file on iOS.
  ///
  /// [ahapPath] - The Flutter asset path of the `.ahap` file (e.g.
  /// `'assets/haptics/rumble.ahap'`), or an absolute file-system path.
  /// [atTime] - (iOS only) Delay in seconds before playback starts.
  ///
  /// On Android, this falls back to a predefined, strong vibration pattern.
  static Future<void> playAhap(String ahapPath, {double atTime = 0.0}) async {
    if (ahapPath.trim().isEmpty) {
      throw ArgumentError.value(ahapPath, 'ahapPath', 'must not be empty');
    }
    _validateTime(atTime, 'atTime');
    await _platform.playAhap(path: ahapPath, atTime: atTime);
  }

  // --------------------------------------------
  // Player control methods (iOS-focused)
  // --------------------------------------------

  /// Pauses the currently active haptic pattern.
  ///
  /// On iOS this pauses the `CHHapticAdvancedPatternPlayer` started by
  /// [playWaveform], [playAhap] or [success]. On Android, which has no native
  /// pause, the plugin remembers the position inside the waveform started by
  /// [playWaveform], [playAhap] or [success] and cancels the vibrator; [resume]
  /// replays the remainder. Predefined effects cannot be paused.
  ///
  /// Throws a `PlatformException` with code `PLAYER_NIL` when no pattern is
  /// playing or paused. Pausing an already paused pattern is a no-op.
  ///
  /// [atTime] - Delay in seconds before pausing. Use `0.0` for immediate.
  /// A delayed pause replies immediately and runs best-effort.
  static Future<void> pause({double atTime = 0.0}) async {
    _validateTime(atTime, 'atTime');
    await _platform.pause(atTime: atTime);
  }

  /// Resumes a paused haptic pattern.
  ///
  /// On Android the remainder of the paused waveform is replayed, including
  /// its loop when it was started with `repeat`. Throws a `PlatformException`
  /// with code `PLAYER_NIL` when no pattern is playing or paused. Resuming a
  /// pattern that is not paused is a no-op.
  ///
  /// [atTime] - Delay in seconds before resuming. Use `0.0` for immediate.
  static Future<void> resume({double atTime = 0.0}) async {
    _validateTime(atTime, 'atTime');
    await _platform.resume(atTime: atTime);
  }

  /// Seeks to a specific point in the active haptic pattern.
  ///
  /// On Android the waveform is restarted from [offset] (or, when paused, the
  /// paused position moves there). For a repeating waveform the offset wraps
  /// around the loop; seeking past the end of a non-repeating waveform ends it.
  /// Throws a `PlatformException` with code `PLAYER_NIL` when no pattern is
  /// playing or paused.
  ///
  /// [offset] - The time, in seconds, to seek to within the pattern.
  static Future<void> seek({required double offset}) async {
    _validateTime(offset, 'offset');
    await _platform.seek(offset: offset);
  }

  /// Stops any currently playing haptic pattern.
  ///
  /// Safe to call when nothing is playing. On iOS, this stops the active
  /// `CHHapticAdvancedPatternPlayer`. On Android, this cancels the `Vibrator`
  /// and forgets any paused pattern.
  ///
  /// [atTime] - Delay in seconds before stopping. Use `0.0` for immediate.
  static Future<void> stop({double atTime = 0.0}) async {
    _validateTime(atTime, 'atTime');
    await _platform.stop(atTime: atTime);
  }

  /// Cancels the haptic player immediately, ignoring any scheduled events.
  ///
  /// Safe to call when nothing is playing. On Android this cancels the
  /// `Vibrator`, the same as [stop].
  static Future<void> cancel() async {
    await _platform.cancel();
  }

  // --------------------------------------------
  // Utility presets
  // --------------------------------------------

  /// Plays a simple, predefined "success" haptic.
  static Future<void> success() async {
    await _platform.success();
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
  ///
  /// Ignored on every other platform. On Android below API 29 a short
  /// vibration of comparable strength is played instead.
  static Future<void> playPredefined(AndroidPredefinedHaptic effect) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    await _platform.playPredefined(effectId: effect.effectId);
  }

  // --------------------------------------------
  // Validation
  // --------------------------------------------

  static void _validateWaveform(
    List<int> timings,
    List<int> amplitudes,
    int repeat,
  ) {
    if (timings.isEmpty) {
      throw ArgumentError.value(timings, 'timings', 'must not be empty');
    }
    if (timings.length != amplitudes.length) {
      throw ArgumentError(
        'Timings and amplitudes lists must have the same length '
        '(got ${timings.length} timings and ${amplitudes.length} amplitudes).',
      );
    }
    for (var i = 0; i < timings.length; i++) {
      if (timings[i] < 0) {
        throw ArgumentError.value(
          timings[i],
          'timings[$i]',
          'must be a non-negative number of milliseconds',
        );
      }
      if (amplitudes[i] < 0 || amplitudes[i] > maxAmplitude) {
        throw RangeError.range(
          amplitudes[i],
          0,
          maxAmplitude,
          'amplitudes[$i]',
        );
      }
    }
    if (repeat < -1 || repeat >= timings.length) {
      throw ArgumentError.value(
        repeat,
        'repeat',
        'must be -1 (no repeat) or an index into timings '
            '(0..${timings.length - 1})',
      );
    }
  }

  static void _validateTime(double value, String name) {
    if (value.isNaN || value.isInfinite || value < 0) {
      throw ArgumentError.value(
        value,
        name,
        'must be a finite, non-negative number of seconds',
      );
    }
  }
}
