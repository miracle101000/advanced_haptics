import 'package:advanced_haptics/advanced_haptics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HapticPatternBuilder', () {
    test('places events sequentially and advances the cursor', () {
      final builder = HapticPatternBuilder()
          .tap(intensity: 0.6, sharpness: 0.3)
          .pause(const Duration(milliseconds: 120))
          .buzz(const Duration(milliseconds: 200), intensity: 0.8);
      expect(builder.position, const Duration(milliseconds: 350));

      final pattern = builder.build();
      expect(pattern.events.length, 2);
      final tap = pattern.events[0] as HapticTransient;
      expect(tap.at, Duration.zero);
      expect(tap.intensity, 0.6);
      expect(tap.sharpness, 0.3);
      final buzz = pattern.events[1] as HapticContinuous;
      expect(buzz.at, const Duration(milliseconds: 150));
      expect(buzz.duration, const Duration(milliseconds: 200));
      expect(pattern.duration, const Duration(milliseconds: 350));
      expect(pattern.isTransientOnly, isFalse);
    });

    test('add keeps absolute times and only moves the cursor forward', () {
      final builder = HapticPatternBuilder()
          .buzz(const Duration(milliseconds: 500))
          .add(const HapticTransient(at: Duration(milliseconds: 100)));
      expect(builder.position, const Duration(milliseconds: 500));
      builder.add(const HapticTransient(at: Duration(milliseconds: 600)));
      expect(builder.position, const Duration(milliseconds: 630));
    });

    test('addPattern shifts a pattern to the cursor', () {
      final heartbeat = HapticPatternBuilder()
          .tap()
          .pause(const Duration(milliseconds: 100))
          .tap()
          .build();
      final twice = HapticPatternBuilder()
          .addPattern(heartbeat)
          .pause(const Duration(milliseconds: 400))
          .addPattern(heartbeat)
          .build();
      expect(twice.events.map((e) => e.at.inMilliseconds), [0, 130, 560, 690]);
    });
  });

  group('HapticPattern.toWaveform', () {
    test('a single tap is a nominal-length pulse', () {
      final wave = const HapticPattern([HapticTransient()]).toWaveform();
      expect(wave.timings, [30]);
      expect(wave.amplitudes, [255]);
    });

    test('leading silence becomes an initial delay segment', () {
      final wave = const HapticPattern([
        HapticTransient(at: Duration(milliseconds: 100), intensity: 0.5),
      ]).toWaveform();
      expect(wave.timings, [100, 30]);
      expect(wave.amplitudes, [0, 128]);
    });

    test('gaps between events are silent segments', () {
      final wave = HapticPatternBuilder()
          .tap()
          .pause(const Duration(milliseconds: 70))
          .tap()
          .build()
          .toWaveform();
      expect(wave.timings, [30, 70, 30]);
      expect(wave.amplitudes, [255, 0, 255]);
    });

    test('overlapping events take the strongest intensity', () {
      final wave = const HapticPattern([
        HapticContinuous(duration: Duration(milliseconds: 100), intensity: 0.5),
        HapticTransient(),
      ]).toWaveform();
      expect(wave.timings, [30, 70]);
      expect(wave.amplitudes, [255, 128]);
    });

    test('adjacent equal amplitudes are merged', () {
      final wave = HapticPatternBuilder()
          .buzz(const Duration(milliseconds: 100))
          .buzz(const Duration(milliseconds: 50))
          .build()
          .toWaveform();
      expect(wave.timings, [150]);
      expect(wave.amplitudes, [255]);
      expect(wave.duration, const Duration(milliseconds: 150));
    });

    test('an empty pattern is an empty waveform', () {
      final wave = const HapticPattern([]).toWaveform();
      expect(wave.isEmpty, isTrue);
    });

    test('the waveform is accepted by playWaveform validation', () async {
      final wave = HapticPatternBuilder()
          .tap()
          .pause(const Duration(milliseconds: 50))
          .buzz(const Duration(milliseconds: 80), intensity: 0.3)
          .build()
          .toWaveform();
      // Same length, non-negative timings, amplitudes within range.
      expect(wave.timings.length, wave.amplitudes.length);
      expect(wave.timings.every((t) => t >= 0), isTrue);
      expect(wave.amplitudes.every((a) => a >= 0 && a <= 255), isTrue);
    });
  });

  group('validation', () {
    test('rejects intensities and sharpness outside 0..1', () {
      expect(() => const HapticTransient(intensity: -0.1).validate(),
          throwsArgumentError);
      expect(() => const HapticTransient(sharpness: 1.1).validate(),
          throwsArgumentError);
    });

    test('rejects negative start times and non-positive durations', () {
      expect(
        () => const HapticTransient(at: Duration(milliseconds: -1)).validate(),
        throwsArgumentError,
      );
      expect(
        () => const HapticContinuous(duration: Duration(milliseconds: -1))
            .validate(),
        throwsArgumentError,
      );
    });
  });

  group('AndroidPrimitiveEvent.toPattern', () {
    test('lays primitives out end to end with their delays', () {
      final pattern = AndroidPrimitiveEvent.toPattern(const [
        AndroidPrimitiveEvent(AndroidHapticPrimitive.click),
        AndroidPrimitiveEvent(AndroidHapticPrimitive.thud,
            scale: 0.5, delay: Duration(milliseconds: 100)),
        AndroidPrimitiveEvent(AndroidHapticPrimitive.slowRise),
      ]);
      expect(pattern.events.length, 3);
      final click = pattern.events[0] as HapticTransient;
      expect(click.at, Duration.zero);
      final thud = pattern.events[1] as HapticTransient;
      expect(thud.at, const Duration(milliseconds: 130));
      expect(thud.intensity, 0.5);
      expect(thud.sharpness, 0.1);
      final rise = pattern.events[2] as HapticContinuous;
      expect(rise.at, const Duration(milliseconds: 190));
      expect(rise.duration, const Duration(milliseconds: 500));
    });

    test('primitive ids match VibrationEffect.Composition', () {
      expect(AndroidHapticPrimitive.click.id, 1);
      expect(AndroidHapticPrimitive.thud.id, 2);
      expect(AndroidHapticPrimitive.spin.id, 3);
      expect(AndroidHapticPrimitive.quickRise.id, 4);
      expect(AndroidHapticPrimitive.slowRise.id, 5);
      expect(AndroidHapticPrimitive.quickFall.id, 6);
      expect(AndroidHapticPrimitive.tick.id, 7);
      expect(AndroidHapticPrimitive.lowTick.id, 8);
      expect(AndroidHapticPrimitive.thud.minApi, 31);
      expect(AndroidHapticPrimitive.click.minApi, 30);
    });
  });
}
