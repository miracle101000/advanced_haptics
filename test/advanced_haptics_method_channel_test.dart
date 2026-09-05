import 'package:advanced_haptics/advanced_haptics_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelAdvancedHaptics platform = MethodChannelAdvancedHaptics();
  const MethodChannel channel =
      MethodChannel(MethodChannelAdvancedHaptics.channelName);

  final List<MethodCall> log = <MethodCall>[];
  Object? Function(MethodCall call)? handler;

  void install(Object? Function(MethodCall call) h) {
    handler = h;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      log.add(call);
      return handler!(call);
    });
  }

  setUp(() {
    log.clear();
    handler = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses the channel the native plugins listen on', () {
    expect(platform.methodChannel.name, 'com.example/advanced_haptics');
  });

  group('hasCustomHapticsSupport', () {
    test('returns the native answer', () async {
      install((_) => true);
      expect(await platform.hasCustomHapticsSupport(), isTrue);
      expect(log.single.method, 'hasCustomHapticsSupport');
    });

    test('returns false when native returns null', () async {
      install((_) => null);
      expect(await platform.hasCustomHapticsSupport(), isFalse);
    });

    test('returns false on a PlatformException', () async {
      install((_) => throw PlatformException(code: 'UNSUPPORTED'));
      expect(await platform.hasCustomHapticsSupport(), isFalse);
    });

    test('returns false when no native implementation exists', () async {
      // No handler installed: the channel throws MissingPluginException.
      expect(await platform.hasCustomHapticsSupport(), isFalse);
    });
  });

  group('playWaveform', () {
    test('encodes all arguments', () async {
      install((_) => null);
      await platform.playWaveform(
        timings: const [0, 100, 50],
        amplitudes: const [0, 255, 0],
        repeat: 1,
        atTime: 0.25,
      );
      final MethodCall call = log.single;
      expect(call.method, 'playWaveform');
      expect(call.arguments, <String, Object?>{
        'timings': [0, 100, 50],
        'amplitudes': [0, 255, 0],
        'repeat': 1,
        'atTime': 0.25,
      });
    });

    test('propagates PlatformException', () async {
      install((_) => throw PlatformException(code: 'VIBRATION_ERROR'));
      expect(
        platform.playWaveform(timings: const [0, 10], amplitudes: const [0, 10]),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'VIBRATION_ERROR')),
      );
    });

    test('is a no-op when no native implementation exists', () async {
      await platform.playWaveform(
          timings: const [0, 10], amplitudes: const [0, 10]);
    });
  });

  test('playAhap encodes path and atTime', () async {
    install((_) => null);
    await platform.playAhap(path: 'assets/x.ahap', atTime: 2);
    expect(log.single.method, 'playAhap');
    expect(log.single.arguments,
        <String, Object?>{'path': 'assets/x.ahap', 'atTime': 2.0});
  });

  test('playPredefined encodes the effect id', () async {
    install((_) => null);
    await platform.playPredefined(effectId: 5);
    expect(log.single.method, 'playPredefined');
    expect(log.single.arguments, <String, Object?>{'effectId': 5});
  });

  test('success sends no arguments', () async {
    install((_) => null);
    await platform.success();
    expect(log.single.method, 'success');
    expect(log.single.arguments, isNull);
  });

  test('player controls encode their times', () async {
    install((_) => null);
    await platform.pause(atTime: 0.1);
    await platform.resume(atTime: 0.2);
    await platform.seek(offset: 0.3);
    await platform.stop(atTime: 0.4);
    await platform.cancel();
    expect(log.map((c) => c.method),
        ['pause', 'resume', 'seek', 'stop', 'cancel']);
    expect(log[0].arguments, <String, Object?>{'atTime': 0.1});
    expect(log[1].arguments, <String, Object?>{'atTime': 0.2});
    expect(log[2].arguments, <String, Object?>{'offset': 0.3});
    expect(log[3].arguments, <String, Object?>{'atTime': 0.4});
    expect(log[4].arguments, isNull);
  });
}
