import 'dart:async';

import 'package:advanced_haptics/advanced_haptics.dart';

enum HapticTaskType { download, scan, charge }

/// Drives a continuous haptic "texture" whose character follows a progress
/// value in `0..1`. Demonstrates how to build feedback for long-running tasks
/// out of short, repeated waveforms.
class HapticEngine {
  HapticEngine(this.type);

  final HapticTaskType type;
  bool _isPlaying = false;
  Timer? _loopTimer;

  bool get isPlaying => _isPlaying;

  /// Starts the continuous haptic loop for the given progress.
  void start(double progress) {
    if (_isPlaying) return;
    _isPlaying = true;
    _loop(progress);
  }

  /// Updates the haptic feedback based on the new progress value.
  void update(double progress) {
    if (!_isPlaying) return;
    // Restart the loop so the new progress is felt immediately.
    _loopTimer?.cancel();
    _loop(progress);
  }

  /// Stops the haptic loop immediately.
  void stop() {
    if (!_isPlaying) return;
    _finish();
    // Explicitly cancel so a waveform that is still running does not linger.
    _fireAndForget(AdvancedHaptics.stop());
  }

  void _finish() {
    _loopTimer?.cancel();
    _loopTimer = null;
    _isPlaying = false;
  }

  /// Haptic calls are fire-and-forget here: on unsupported hardware they are
  /// no-ops, and a failure must not break the loop.
  void _fireAndForget(Future<void> future) {
    future.catchError((Object _) {});
  }

  /// The main loop that generates the haptic patterns.
  void _loop(double progress) {
    final p = progress.clamp(0.0, 1.0);
    switch (type) {
      case HapticTaskType.download:
        _runDownloadLoop(p);
      case HapticTaskType.scan:
        _runScanLoop(p);
      case HapticTaskType.charge:
        _runChargeLoop(p);
    }
  }

  void _runDownloadLoop(double p) {
    // A continuous, low rumble that gets slightly more intense.
    final intensity = (100 + (p * 80)).toInt(); // 100..180
    _fireAndForget(AdvancedHaptics.playWaveform([0, 50], [0, intensity]));

    // Re-trigger every 55 ms so it feels continuous.
    _loopTimer = Timer(const Duration(milliseconds: 55), () {
      if (_isPlaying) _loop(p);
    });
  }

  void _runScanLoop(double p) {
    // A rhythmic tick that gets faster: delay from 400 ms down to 50 ms.
    final delay = (400 - (p * 350)).toInt();
    _fireAndForget(AdvancedHaptics.playWaveform(const [0, 20], const [0, 255]));

    _loopTimer = Timer(Duration(milliseconds: delay), () {
      if (_isPlaying) _loop(p);
    });
  }

  void _runChargeLoop(double p) {
    // A swelling vibration that increases in intensity.
    final intensity = (50 + (p * 205)).toInt().clamp(0, 255); // 50..255
    _fireAndForget(AdvancedHaptics.playWaveform([0, 100], [0, intensity]));

    if (p >= 1.0) {
      // Reached 100%: play a final thump and finish. Do not call stop() here,
      // it would cancel the thump before it is felt.
      _loopTimer = Timer(const Duration(milliseconds: 120), () {
        _fireAndForget(AdvancedHaptics.playWaveform(const [0, 150], const [0, 255]));
        _finish();
      });
    } else {
      _loopTimer = Timer(const Duration(milliseconds: 110), () {
        if (_isPlaying) _loop(p);
      });
    }
  }
}
