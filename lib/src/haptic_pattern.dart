import 'dart:math' as math;

/// A single event in a [HapticPattern].
///
/// Events are positioned on an absolute timeline ([at]) and carry an
/// [intensity] (strength) and a [sharpness] (feel). On iOS both map directly
/// to Core Haptics parameters. On Android the sharpness selects the closest
/// `VibrationEffect.Composition` primitive when primitives are available and
/// is otherwise ignored.
sealed class HapticEvent {
  const HapticEvent({
    required this.at,
    required this.intensity,
    required this.sharpness,
  });

  /// When the event starts, relative to the start of the pattern.
  final Duration at;

  /// Strength, from `0.0` (imperceptible) to `1.0` (maximum).
  final double intensity;

  /// Feel, from `0.0` (soft, round, low frequency) to `1.0` (crisp, sharp).
  final double sharpness;

  /// How long the event occupies the timeline when rendered as a waveform.
  Duration get renderedDuration;

  /// When the event ends on the waveform timeline.
  Duration get end => at + renderedDuration;

  /// Serialises the event for the platform channel.
  Map<String, Object?> toJson();

  /// Throws an [ArgumentError] when the event is out of range.
  void validate() {
    if (at < Duration.zero) {
      throw ArgumentError.value(at, 'at', 'must not be negative');
    }
    _checkUnit(intensity, 'intensity');
    _checkUnit(sharpness, 'sharpness');
  }

  static void _checkUnit(double value, String name) {
    if (value.isNaN || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'must be between 0.0 and 1.0');
    }
  }

  static double _seconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;
}

/// A short, tap-like haptic.
///
/// Rendered as a Core Haptics transient event on iOS, as a `CLICK`, `TICK`
/// or `THUD` primitive on Android 11+ (chosen by [sharpness]), and as a
/// [nominalDuration] pulse in a waveform elsewhere.
final class HapticTransient extends HapticEvent {
  const HapticTransient({
    super.at = Duration.zero,
    super.intensity = 1.0,
    super.sharpness = 0.5,
  });

  /// Width of a transient when it has to be rendered as a waveform pulse.
  static const Duration nominalDuration = Duration(milliseconds: 30);

  @override
  Duration get renderedDuration => nominalDuration;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'transient',
        'time': HapticEvent._seconds(at),
        'intensity': intensity,
        'sharpness': sharpness,
      };
}

/// A sustained haptic that lasts for [duration].
///
/// Rendered as a Core Haptics continuous event on iOS and as a waveform
/// segment on Android.
final class HapticContinuous extends HapticEvent {
  const HapticContinuous({
    required this.duration,
    super.at = Duration.zero,
    super.intensity = 1.0,
    super.sharpness = 0.5,
  });

  /// How long the haptic lasts. Must be positive.
  final Duration duration;

  @override
  Duration get renderedDuration => duration;

  @override
  void validate() {
    super.validate();
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'must be positive');
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'continuous',
        'time': HapticEvent._seconds(at),
        'duration': HapticEvent._seconds(duration),
        'intensity': intensity,
        'sharpness': sharpness,
      };
}

/// An Android-style waveform: segment [timings] in milliseconds and
/// [amplitudes] from 0 to 255, both the same length.
final class HapticWaveform {
  const HapticWaveform(this.timings, this.amplitudes);

  final List<int> timings;
  final List<int> amplitudes;

  bool get isEmpty => timings.isEmpty;

  Duration get duration =>
      Duration(milliseconds: timings.fold(0, (sum, t) => sum + t));
}

/// A platform-independent haptic pattern made of [HapticEvent]s.
///
/// Build one with [HapticPatternBuilder] or construct it directly, then play
/// it with `AdvancedHaptics.playPattern`. The same pattern renders as Core
/// Haptics events on iOS, as composition primitives or a waveform on Android,
/// and as a waveform-driven fallback on hardware without either.
final class HapticPattern {
  const HapticPattern(this.events);

  /// The events, in any order; they are sorted by [HapticEvent.at] when played.
  final List<HapticEvent> events;

  bool get isEmpty => events.isEmpty;

  /// Whether the pattern consists only of [HapticTransient]s, which lets
  /// Android render it with composition primitives.
  bool get isTransientOnly => events.every((e) => e is HapticTransient);

  /// The end of the last event on the waveform timeline.
  Duration get duration => events.fold(
        Duration.zero,
        (latest, e) => e.end > latest ? e.end : latest,
      );

  /// Throws an [ArgumentError] when any event is out of range.
  void validate() {
    for (final event in events) {
      event.validate();
    }
  }

  /// The events sorted by start time, serialised for the platform channel.
  List<Map<String, Object?>> toJson() {
    final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
    return [for (final e in sorted) e.toJson()];
  }

  /// Flattens the pattern into an amplitude waveform.
  ///
  /// Overlapping events take the strongest intensity. Transients become
  /// [HapticTransient.nominalDuration] pulses. Sharpness is not representable
  /// in a waveform and is dropped. Consecutive segments with equal amplitude
  /// are merged and zero-length segments removed, so the result is always
  /// valid input for `AdvancedHaptics.playWaveform`.
  HapticWaveform toWaveform() {
    if (events.isEmpty) return const HapticWaveform([], []);

    // Boundaries in milliseconds where the amplitude may change.
    final boundaries = <int>{0};
    for (final e in events) {
      boundaries
        ..add(e.at.inMilliseconds)
        ..add(e.end.inMilliseconds);
    }
    final points = boundaries.toList()..sort();

    final timings = <int>[];
    final amplitudes = <int>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final stop = points[i + 1];
      if (stop <= start) continue;
      var intensity = 0.0;
      for (final e in events) {
        if (e.at.inMilliseconds <= start && e.end.inMilliseconds >= stop) {
          intensity = math.max(intensity, e.intensity);
        }
      }
      final amplitude = (intensity * 255).round().clamp(0, 255);
      if (amplitudes.isNotEmpty && amplitudes.last == amplitude) {
        timings[timings.length - 1] += stop - start;
      } else {
        timings.add(stop - start);
        amplitudes.add(amplitude);
      }
    }
    return HapticWaveform(
      List<int>.unmodifiable(timings),
      List<int>.unmodifiable(amplitudes),
    );
  }
}

/// Builds a [HapticPattern] sequentially: each call appends at the current
/// [position] and advances it, so `tap().pause(...).buzz(...)` reads like
/// the pattern feels.
///
/// ```dart
/// final heartbeat = HapticPatternBuilder()
///     .tap(intensity: 0.6, sharpness: 0.3)
///     .pause(const Duration(milliseconds: 120))
///     .tap(intensity: 1.0, sharpness: 0.3)
///     .build();
/// await AdvancedHaptics.playPattern(heartbeat);
/// ```
final class HapticPatternBuilder {
  HapticPatternBuilder();

  final List<HapticEvent> _events = <HapticEvent>[];
  Duration _cursor = Duration.zero;

  /// Where the next event will be placed.
  Duration get position => _cursor;

  /// Appends a [HapticTransient] and advances by its
  /// [HapticTransient.nominalDuration].
  HapticPatternBuilder tap({double intensity = 1.0, double sharpness = 0.5}) {
    _events.add(
      HapticTransient(at: _cursor, intensity: intensity, sharpness: sharpness),
    );
    _cursor += HapticTransient.nominalDuration;
    return this;
  }

  /// Appends a [HapticContinuous] of [duration] and advances past it.
  HapticPatternBuilder buzz(
    Duration duration, {
    double intensity = 1.0,
    double sharpness = 0.5,
  }) {
    _events.add(HapticContinuous(
      at: _cursor,
      duration: duration,
      intensity: intensity,
      sharpness: sharpness,
    ));
    _cursor += duration;
    return this;
  }

  /// Leaves a gap of [duration].
  HapticPatternBuilder pause(Duration duration) {
    _cursor += duration;
    return this;
  }

  /// Adds an event at its own absolute time. The cursor moves to the end of
  /// the event only when that is later than the current position.
  HapticPatternBuilder add(HapticEvent event) {
    _events.add(event);
    if (event.end > _cursor) _cursor = event.end;
    return this;
  }

  /// Appends every event of [pattern], shifted to start at the current
  /// position, and advances past it.
  HapticPatternBuilder addPattern(HapticPattern pattern) {
    final offset = _cursor;
    for (final e in pattern.events) {
      switch (e) {
        case HapticTransient():
          _events.add(HapticTransient(
            at: offset + e.at,
            intensity: e.intensity,
            sharpness: e.sharpness,
          ));
        case HapticContinuous():
          _events.add(HapticContinuous(
            at: offset + e.at,
            duration: e.duration,
            intensity: e.intensity,
            sharpness: e.sharpness,
          ));
      }
    }
    _cursor = offset + pattern.duration;
    return this;
  }

  HapticPattern build() => HapticPattern(List<HapticEvent>.unmodifiable(_events));
}
