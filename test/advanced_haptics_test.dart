import 'package:advanced_haptics/advanced_haptics.dart';
import 'package:advanced_haptics/advanced_haptics_method_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Records every call so tests can assert on what reached the platform.
class RecordingPlatform
    with MockPlatformInterfaceMixin
    implements AdvancedHapticsPlatform {
  final List<String> calls = <String>[];
  final Map<String, Object?> lastArgs = <String, Object?>{};
  bool supportResult = true;
  Object? errorToThrow;

  Future<T> _record<T>(String name, T value, [Map<String, Object?>? args]) {
    calls.add(name);
    lastArgs
      ..clear()
      ..addAll(args ?? const <String, Object?>{});
    final Object? error = errorToThrow;
    if (error != null) {
      return Future<T>.error(error);
    }
    return Future<T>.value(value);
  }

  @override
  Future<bool> hasCustomHapticsSupport() =>
      _record('hasCustomHapticsSupport', supportResult);

  @override
  Future<void> playWaveform({
    required List<int> timings,
    required List<int> amplitudes,
    int repeat = -1,
    double atTime = 0.0,
  }) =>
      _record('playWaveform', null, <String, Object?>{
        'timings': timings,
        'amplitudes': amplitudes,
        'repeat': repeat,
        'atTime': atTime,
      });

  @override
  Future<void> playAhap({required String path, double atTime = 0.0}) =>
      _record('playAhap', null, <String, Object?>{
        'path': path,
        'atTime': atTime,
      });

  @override
  Future<void> playPredefined({required int effectId}) =>
      _record('playPredefined', null, <String, Object?>{'effectId': effectId});

  @override
  Future<void> success() => _record('success', null);

  @override
  Future<void> pause({double atTime = 0.0}) =>
      _record('pause', null, <String, Object?>{'atTime': atTime});

  @override
  Future<void> resume({double atTime = 0.0}) =>
      _record('resume', null, <String, Object?>{'atTime': atTime});

  @override
  Future<void> seek({required double offset}) =>
      _record('seek', null, <String, Object?>{'offset': offset});

  @override
  Future<void> stop({double atTime = 0.0}) =>
      _record('stop', null, <String, Object?>{'atTime': atTime});

  @override
  Future<void> cancel() => _record('cancel', null);
}

void main() {
  final AdvancedHapticsPlatform initialPlatform =
      AdvancedHapticsPlatform.instance;
  late RecordingPlatform platform;

  setUp(() {
    platform = RecordingPlatform();
    AdvancedHapticsPlatform.instance = platform;
  });

  tearDown(() {
    AdvancedHapticsPlatform.instance = initialPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  test('$MethodChannelAdvancedHaptics is the default instance', () {
    expect(initialPlatform, isA<MethodChannelAdvancedHaptics>());
  });

  group('hasCustomHapticsSupport', () {
    test('forwards the platform answer', () async {
      platform.supportResult = true;
      expect(await AdvancedHaptics.hasCustomHapticsSupport(), isTrue);
      platform.supportResult = false;
      expect(await AdvancedHaptics.hasCustomHapticsSupport(), isFalse);
    });

    test('returns false instead of throwing when the platform fails',
        () async {
      platform.errorToThrow = StateError('boom');
      expect(await AdvancedHaptics.hasCustomHapticsSupport(), isFalse);
    });
  });

  group('playWaveform', () {
    test('forwards timings, amplitudes, repeat and atTime', () async {
      await AdvancedHaptics.playWaveform(
        [0, 100, 200],
        [0, 255, 0],
        repeat: 1,
        atTime: 0.5,
      );
      expect(platform.calls, ['playWaveform']);
      expect(platform.lastArgs['timings'], [0, 100, 200]);
      expect(platform.lastArgs['amplitudes'], [0, 255, 0]);
      expect(platform.lastArgs['repeat'], 1);
      expect(platform.lastArgs['atTime'], 0.5);
    });

    test('defaults to no repeat and immediate playback', () async {
      await AdvancedHaptics.playWaveform([0, 30], [0, 180]);
      expect(platform.lastArgs['repeat'], -1);
      expect(platform.lastArgs['atTime'], 0.0);
    });

    test('rejects empty lists', () {
      expect(
        () => AdvancedHaptics.playWaveform([], []),
        throwsArgumentError,
      );
      expect(platform.calls, isEmpty);
    });

    test('rejects mismatched lengths', () {
      expect(
        () => AdvancedHaptics.playWaveform([0, 100], [0]),
        throwsArgumentError,
      );
      expect(platform.calls, isEmpty);
    });

    test('rejects negative timings', () {
      expect(
        () => AdvancedHaptics.playWaveform([0, -5], [0, 100]),
        throwsArgumentError,
      );
      expect(platform.calls, isEmpty);
    });

    test('rejects amplitudes outside 0..255', () {
      expect(
        () => AdvancedHaptics.playWaveform([0, 10], [0, 256]),
        throwsRangeError,
      );
      expect(
        () => AdvancedHaptics.playWaveform([0, 10], [-1, 100]),
        throwsRangeError,
      );
      expect(platform.calls, isEmpty);
    });

    test('accepts the amplitude boundaries', () async {
      await AdvancedHaptics.playWaveform(
        [0, 10],
        [0, AdvancedHaptics.maxAmplitude],
      );
      expect(platform.calls, ['playWaveform']);
    });

    test('rejects an out-of-range repeat index', () {
      expect(
        () => AdvancedHaptics.playWaveform([0, 10], [0, 10], repeat: 2),
        throwsArgumentError,
      );
      expect(
        () => AdvancedHaptics.playWaveform([0, 10], [0, 10], repeat: -2),
        throwsArgumentError,
      );
      expect(platform.calls, isEmpty);
    });

    test('rejects a negative or non-finite atTime', () {
      expect(
        () => AdvancedHaptics.playWaveform([0, 10], [0, 10], atTime: -1),
        throwsArgumentError,
      );
      expect(
        () => AdvancedHaptics.playWaveform([0, 10], [0, 10],
            atTime: double.nan),
        throwsArgumentError,
      );
      expect(platform.calls, isEmpty);
    });

    test('propagates platform errors', () {
      platform.errorToThrow = StateError('native failure');
      expect(
        AdvancedHaptics.playWaveform([0, 10], [0, 10]),
        throwsStateError,
      );
    });
  });

  group('presets', () {
    test('each preset sends a valid waveform', () async {
      await AdvancedHaptics.lightTap();
      await AdvancedHaptics.mediumTap();
      await AdvancedHaptics.heavyRumble();
      await AdvancedHaptics.successBuzz();
      await AdvancedHaptics.error();
      await AdvancedHaptics.selectionClick();
      expect(platform.calls, List<String>.filled(6, 'playWaveform'));
    });

    test('success uses the native preset', () async {
      await AdvancedHaptics.success();
      expect(platform.calls, ['success']);
    });
  });

  group('playAhap', () {
    test('forwards the path and atTime', () async {
      await AdvancedHaptics.playAhap('assets/haptics/rumble.ahap',
          atTime: 1.5);
      expect(platform.calls, ['playAhap']);
      expect(platform.lastArgs['path'], 'assets/haptics/rumble.ahap');
      expect(platform.lastArgs['atTime'], 1.5);
    });

    test('rejects an empty path', () {
      expect(() => AdvancedHaptics.playAhap('  '), throwsArgumentError);
      expect(platform.calls, isEmpty);
    });
  });

  group('player controls', () {
    test('forward their arguments', () async {
      await AdvancedHaptics.pause(atTime: 0.1);
      expect(platform.lastArgs['atTime'], 0.1);
      await AdvancedHaptics.resume(atTime: 0.2);
      expect(platform.lastArgs['atTime'], 0.2);
      await AdvancedHaptics.seek(offset: 0.3);
      expect(platform.lastArgs['offset'], 0.3);
      await AdvancedHaptics.stop(atTime: 0.4);
      expect(platform.lastArgs['atTime'], 0.4);
      await AdvancedHaptics.cancel();
      expect(platform.calls, ['pause', 'resume', 'seek', 'stop', 'cancel']);
    });

    test('reject negative times', () {
      expect(() => AdvancedHaptics.pause(atTime: -1), throwsArgumentError);
      expect(() => AdvancedHaptics.resume(atTime: -1), throwsArgumentError);
      expect(() => AdvancedHaptics.seek(offset: -1), throwsArgumentError);
      expect(() => AdvancedHaptics.stop(atTime: -1), throwsArgumentError);
      expect(platform.calls, isEmpty);
    });
  });

  group('playPredefined', () {
    test('sends the effect id on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await AdvancedHaptics.playPredefined(AndroidPredefinedHaptic.heavyClick);
      expect(platform.calls, ['playPredefined']);
      expect(platform.lastArgs['effectId'], 5);
    });

    test('is skipped on other platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await AdvancedHaptics.playPredefined(AndroidPredefinedHaptic.tick);
      expect(platform.calls, isEmpty);
    });

    test('effect ids match android.os.VibrationEffect', () {
      expect(AndroidPredefinedHaptic.click.effectId, 0);
      expect(AndroidPredefinedHaptic.doubleClick.effectId, 1);
      expect(AndroidPredefinedHaptic.tick.effectId, 2);
      expect(AndroidPredefinedHaptic.thud.effectId, 3);
      expect(AndroidPredefinedHaptic.pop.effectId, 4);
      expect(AndroidPredefinedHaptic.heavyClick.effectId, 5);
      expect(AndroidPredefinedHaptic.ringtone1.effectId, 6);
      expect(AndroidPredefinedHaptic.textureTick.effectId, 21);
    });
  });
}
