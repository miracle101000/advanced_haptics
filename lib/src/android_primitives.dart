import 'haptic_pattern.dart';

/// Primitives of Android's `VibrationEffect.Composition` (API 30+).
///
/// [click], [tick], [quickRise], [slowRise] and [quickFall] exist since
/// Android 11 (API 30); [thud], [spin] and [lowTick] since Android 12
/// (API 31). Whether a device can actually play a primitive is hardware
/// dependent; use `AdvancedHaptics.supportsAndroidPrimitives` to check, or
/// just play and let the plugin fall back to a waveform approximation.
enum AndroidHapticPrimitive {
  /// `PRIMITIVE_CLICK`: a crisp, medium-strength click.
  click(1, minApi: 30),

  /// `PRIMITIVE_THUD`: a soft, low-frequency thump.
  thud(2, minApi: 31),

  /// `PRIMITIVE_SPIN`: a short spinning texture.
  spin(3, minApi: 31),

  /// `PRIMITIVE_QUICK_RISE`: a fast ramp up.
  quickRise(4, minApi: 30),

  /// `PRIMITIVE_SLOW_RISE`: a slow ramp up.
  slowRise(5, minApi: 30),

  /// `PRIMITIVE_QUICK_FALL`: a fast ramp down.
  quickFall(6, minApi: 30),

  /// `PRIMITIVE_TICK`: a light, very short tick.
  tick(7, minApi: 30),

  /// `PRIMITIVE_LOW_TICK`: a softer, lower tick.
  lowTick(8, minApi: 31);

  const AndroidHapticPrimitive(this.id, {required this.minApi});

  /// The raw `VibrationEffect.Composition.PRIMITIVE_*` value.
  final int id;

  /// The Android API level that introduced the primitive.
  final int minApi;

  /// Approximate length of the primitive, used to place the next one when
  /// the composition is rendered on the pattern timeline.
  Duration get nominalDuration => switch (this) {
        click => const Duration(milliseconds: 30),
        thud => const Duration(milliseconds: 60),
        spin => const Duration(milliseconds: 150),
        quickRise => const Duration(milliseconds: 150),
        slowRise => const Duration(milliseconds: 500),
        quickFall => const Duration(milliseconds: 100),
        tick => const Duration(milliseconds: 20),
        lowTick => const Duration(milliseconds: 20),
      };

  /// The closest [HapticEvent] for this primitive, used on iOS and on Android
  /// devices without primitive support.
  HapticEvent toEvent({required Duration at, required double scale}) =>
      switch (this) {
        click => HapticTransient(at: at, intensity: scale, sharpness: 0.6),
        thud => HapticTransient(at: at, intensity: scale, sharpness: 0.1),
        tick => HapticTransient(at: at, intensity: scale * 0.7, sharpness: 1.0),
        lowTick =>
          HapticTransient(at: at, intensity: scale * 0.5, sharpness: 0.3),
        spin => HapticContinuous(
            at: at, duration: nominalDuration, intensity: scale, sharpness: 0.5),
        quickRise => HapticContinuous(
            at: at, duration: nominalDuration, intensity: scale, sharpness: 0.7),
        slowRise => HapticContinuous(
            at: at,
            duration: nominalDuration,
            intensity: scale * 0.8,
            sharpness: 0.4),
        quickFall => HapticContinuous(
            at: at, duration: nominalDuration, intensity: scale, sharpness: 0.5),
      };
}

/// One primitive in an Android composition.
///
/// Mirrors `VibrationEffect.Composition.addPrimitive(primitive, scale, delay)`:
/// [delay] is measured from the end of the previous primitive.
final class AndroidPrimitiveEvent {
  const AndroidPrimitiveEvent(
    this.primitive, {
    this.scale = 1.0,
    this.delay = Duration.zero,
  });

  final AndroidHapticPrimitive primitive;

  /// Strength from `0.0` to `1.0`.
  final double scale;

  /// Gap after the previous primitive ends.
  final Duration delay;

  /// Throws an [ArgumentError] when out of range.
  void validate() {
    if (scale.isNaN || scale < 0 || scale > 1) {
      throw ArgumentError.value(scale, 'scale', 'must be between 0.0 and 1.0');
    }
    if (delay < Duration.zero) {
      throw ArgumentError.value(delay, 'delay', 'must not be negative');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': primitive.id,
        'scale': scale,
        'delayMs': delay.inMilliseconds,
      };

  /// Lays a composition out on an absolute timeline as a [HapticPattern],
  /// using each primitive's [AndroidHapticPrimitive.nominalDuration].
  static HapticPattern toPattern(List<AndroidPrimitiveEvent> primitives) {
    final events = <HapticEvent>[];
    var cursor = Duration.zero;
    for (final p in primitives) {
      final start = cursor + p.delay;
      events.add(p.primitive.toEvent(at: start, scale: p.scale));
      cursor = start + p.primitive.nominalDuration;
    }
    return HapticPattern(List<HapticEvent>.unmodifiable(events));
  }
}
