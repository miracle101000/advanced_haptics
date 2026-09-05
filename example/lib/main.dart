import 'package:advanced_haptics/advanced_haptics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'advanced.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HapticsDemoPage());
  }
}

class HapticsDemoPage extends StatefulWidget {
  const HapticsDemoPage({super.key});

  @override
  State<HapticsDemoPage> createState() => _HapticsDemoPageState();
}

class _HapticsDemoPageState extends State<HapticsDemoPage> {
  bool? _hasSupport;
  final HapticEngine _chargeEngine = HapticEngine(HapticTaskType.charge);
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  @override
  void dispose() {
    _chargeEngine.stop();
    super.dispose();
  }

  Future<void> _checkSupport() async {
    final hasSupport = await AdvancedHaptics.hasCustomHapticsSupport();
    if (mounted) {
      setState(() => _hasSupport = hasSupport);
    }
  }

  /// Runs a haptic call and shows failures instead of leaving an unhandled
  /// future error. Invalid arguments and native errors are the two things
  /// that can go wrong.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException catch (e) {
      _showMessage('${e.code}: ${e.message ?? ''}');
    } on ArgumentError catch (e) {
      _showMessage('Invalid arguments: ${e.message}');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final support = _hasSupport;

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Haptics Example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Custom haptics support'),
            subtitle: const Text('Amplitude control / Core Haptics'),
            trailing: Text(
              support == null
                  ? 'Checking…'
                  : support
                      ? '✅ Supported'
                      : '❌ Fallback only',
              style: TextStyle(
                color: support == null
                    ? null
                    : support
                        ? Colors.green
                        : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(),
          _Section(
            title: 'Presets',
            children: [
              _button('Light tap', () => AdvancedHaptics.lightTap()),
              _button('Medium tap', () => AdvancedHaptics.mediumTap()),
              _button('Heavy rumble', () => AdvancedHaptics.heavyRumble()),
              _button('Selection click', () => AdvancedHaptics.selectionClick()),
              _button('Success', () => AdvancedHaptics.success()),
              _button('Success buzz', () => AdvancedHaptics.successBuzz()),
              _button('Error', () => AdvancedHaptics.error()),
            ],
          ),
          _Section(
            title: 'Waveforms',
            children: [
              _button(
                'Custom waveform',
                // Wait 0 ms, vibrate 100 ms, pause 200 ms, vibrate 300 ms.
                () => AdvancedHaptics.playWaveform(
                  [0, 100, 200, 300],
                  [0, 150, 0, 255],
                ),
              ),
              _button(
                'Loop until stopped',
                // Long buzz, then ticks forever (from index 2) until stop().
                () => AdvancedHaptics.playWaveform(
                  [0, 400, 150, 40],
                  [0, 255, 0, 160],
                  repeat: 2,
                ),
              ),
              _button(
                'Stop',
                () => AdvancedHaptics.stop(),
                color: Colors.red,
              ),
            ],
          ),
          _Section(
            title: '.ahap file (iOS) / fallback pattern (Android)',
            children: [
              _button(
                'Play rumble.ahap',
                () => AdvancedHaptics.playAhap('assets/haptics/rumble.ahap'),
              ),
              _button(
                'Play in 1 second',
                () => AdvancedHaptics.playAhap(
                  'assets/haptics/rumble.ahap',
                  atTime: 1.0,
                ),
              ),
            ],
          ),
          if (isAndroid)
            _Section(
              title: 'Android predefined effects (API 29+)',
              children: [
                for (final effect in AndroidPredefinedHaptic.values)
                  _button(
                    effect.name,
                    () => AdvancedHaptics.playPredefined(effect),
                  ),
              ],
            ),
          if (isIOS)
            _Section(
              title: 'iOS player controls',
              children: [
                _button('Pause', () => AdvancedHaptics.pause()),
                _button('Resume', () => AdvancedHaptics.resume()),
                _button('Seek to 0.5 s', () => AdvancedHaptics.seek(offset: 0.5)),
                _button('Cancel', () => AdvancedHaptics.cancel()),
              ],
            ),
          _Section(
            title: 'Progress-driven haptics',
            children: [
              SizedBox(
                width: double.infinity,
                child: Slider(
                  value: _progress,
                  label: '${(_progress * 100).round()}%',
                  divisions: 20,
                  onChanged: (value) {
                    setState(() => _progress = value);
                    _chargeEngine.update(value);
                  },
                ),
              ),
              _button(
                _chargeEngine.isPlaying ? 'Stop charging' : 'Start charging',
                () async {
                  if (_chargeEngine.isPlaying) {
                    _chargeEngine.stop();
                  } else {
                    _chargeEngine.start(_progress);
                  }
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _button(String label, Future<void> Function() action, {Color? color}) {
    return ElevatedButton(
      style: color == null
          ? null
          : ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
      onPressed: () => _run(action),
      child: Text(label),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}
