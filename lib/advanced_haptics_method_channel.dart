import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'advanced_haptics_platform_interface.dart';

/// An implementation of [AdvancedHapticsPlatform] that uses method channels.
class MethodChannelAdvancedHaptics extends AdvancedHapticsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('advanced_haptics');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
