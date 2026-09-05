import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'advanced_haptics_method_channel.dart';

/// The interface that platform implementations of `advanced_haptics` must
/// implement.
///
/// Platform implementations should extend this class rather than implement it,
/// so that newly added methods with default behaviour do not break them.
///
/// Apps can replace [instance] with a mock in tests to observe or silence
/// haptic calls.
abstract class AdvancedHapticsPlatform extends PlatformInterface {
  /// Constructs an [AdvancedHapticsPlatform].
  AdvancedHapticsPlatform() : super(token: _token);

  static final Object _token = Object();

  static AdvancedHapticsPlatform _instance = MethodChannelAdvancedHaptics();

  /// The default instance of [AdvancedHapticsPlatform] to use.
  ///
  /// Defaults to [MethodChannelAdvancedHaptics].
  static AdvancedHapticsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AdvancedHapticsPlatform] when
  /// they register themselves.
  static set instance(AdvancedHapticsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether the device supports custom (amplitude-controlled) haptics.
  Future<bool> hasCustomHapticsSupport() {
    throw UnimplementedError(
        'hasCustomHapticsSupport() has not been implemented.');
  }

  /// Plays a waveform made of [timings] (milliseconds) and [amplitudes]
  /// (0-255). Both lists have already been validated by the public API.
  Future<void> playWaveform({
    required List<int> timings,
    required List<int> amplitudes,
    int repeat = -1,
    double atTime = 0.0,
  }) {
    throw UnimplementedError('playWaveform() has not been implemented.');
  }

  /// Plays an Apple Core Haptics `.ahap` file located at asset [path].
  Future<void> playAhap({required String path, double atTime = 0.0}) {
    throw UnimplementedError('playAhap() has not been implemented.');
  }

  /// Plays an Android predefined vibration effect identified by [effectId].
  Future<void> playPredefined({required int effectId}) {
    throw UnimplementedError('playPredefined() has not been implemented.');
  }

  /// Plays the built-in "success" pattern.
  Future<void> success() {
    throw UnimplementedError('success() has not been implemented.');
  }

  /// Pauses the active player.
  Future<void> pause({double atTime = 0.0}) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  /// Resumes the active player.
  Future<void> resume({double atTime = 0.0}) {
    throw UnimplementedError('resume() has not been implemented.');
  }

  /// Seeks the active player to [offset] seconds.
  Future<void> seek({required double offset}) {
    throw UnimplementedError('seek() has not been implemented.');
  }

  /// Stops any playing haptic.
  Future<void> stop({double atTime = 0.0}) {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// Cancels any playing or scheduled haptic immediately.
  Future<void> cancel() {
    throw UnimplementedError('cancel() has not been implemented.');
  }
}
