import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'advanced_haptics_platform_interface.dart';

/// An implementation of [AdvancedHapticsPlatform] that uses method channels.
class MethodChannelAdvancedHaptics extends AdvancedHapticsPlatform {
  /// The name of the method channel shared with the native implementations.
  static const String channelName = 'com.example/advanced_haptics';

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(channelName);

  /// Invokes [method] on the native side.
  ///
  /// Platforms without a native implementation (web, desktop, unit tests)
  /// throw [MissingPluginException]. Haptics are a progressive enhancement, so
  /// that case is treated as "unsupported" and yields `null` instead of
  /// crashing the caller. [PlatformException]s from the native side are
  /// propagated unchanged.
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> hasCustomHapticsSupport() async {
    try {
      return await _invoke<bool>('hasCustomHapticsSupport') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> playWaveform({
    required List<int> timings,
    required List<int> amplitudes,
    int repeat = -1,
    double atTime = 0.0,
  }) {
    return _invoke<void>('playWaveform', <String, Object?>{
      'timings': timings,
      'amplitudes': amplitudes,
      'repeat': repeat,
      'atTime': atTime,
    });
  }

  @override
  Future<void> playPattern({
    required List<Map<String, Object?>> events,
    required List<int> timings,
    required List<int> amplitudes,
    double atTime = 0.0,
  }) {
    return _invoke<void>('playPattern', <String, Object?>{
      'events': events,
      'timings': timings,
      'amplitudes': amplitudes,
      'atTime': atTime,
    });
  }

  @override
  Future<void> playComposition({
    required List<Map<String, Object?>> primitives,
    required List<int> timings,
    required List<int> amplitudes,
  }) {
    return _invoke<void>('playComposition', <String, Object?>{
      'primitives': primitives,
      'timings': timings,
      'amplitudes': amplitudes,
    });
  }

  @override
  Future<bool> arePrimitivesSupported({required List<int> ids}) async {
    try {
      return await _invoke<bool>(
              'arePrimitivesSupported', <String, Object?>{'ids': ids}) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> playAhap({required String path, double atTime = 0.0}) {
    return _invoke<void>('playAhap', <String, Object?>{
      'path': path,
      'atTime': atTime,
    });
  }

  @override
  Future<void> playPredefined({required int effectId}) {
    return _invoke<void>('playPredefined', <String, Object?>{
      'effectId': effectId,
    });
  }

  @override
  Future<void> success() => _invoke<void>('success');

  @override
  Future<void> pause({double atTime = 0.0}) {
    return _invoke<void>('pause', <String, Object?>{'atTime': atTime});
  }

  @override
  Future<void> resume({double atTime = 0.0}) {
    return _invoke<void>('resume', <String, Object?>{'atTime': atTime});
  }

  @override
  Future<void> seek({required double offset}) {
    return _invoke<void>('seek', <String, Object?>{'offset': offset});
  }

  @override
  Future<void> stop({double atTime = 0.0}) {
    return _invoke<void>('stop', <String, Object?>{'atTime': atTime});
  }

  @override
  Future<void> cancel() => _invoke<void>('cancel');
}
