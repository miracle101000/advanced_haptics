package com.example.advanced_haptics

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.annotation.ChecksSdkIntAtLeast
import androidx.annotation.VisibleForTesting
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Android implementation of the `advanced_haptics` plugin.
 *
 * Every vibration call is guarded: a device without a vibrator silently
 * succeeds, a missing `VIBRATE` permission or an invalid effect is reported as
 * a `PlatformException` with a descriptive code, and nothing here can crash
 * the host app. Amplitude control needs API 26; older devices play the on/off
 * shape of the pattern through the legacy `Vibrator` API.
 */
class AdvancedHapticsPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.example/advanced_haptics"

        const val ERROR_INVALID_ARGS = "INVALID_ARGS"
        const val ERROR_VIBRATION = "VIBRATION_ERROR"
        const val ERROR_PERMISSION = "PERMISSION_DENIED"

        private const val MAX_AMPLITUDE = 255
        private const val NO_REPEAT = -1

        /** Waveform played when an `.ahap` file is requested on Android. */
        private val AHAP_FALLBACK_TIMINGS = longArrayOf(0, 100, 50, 100)
        private val AHAP_FALLBACK_AMPLITUDES = intArrayOf(0, 255, 0, 150)

        private val SUCCESS_TIMINGS = longArrayOf(0, 50, 100, 50)
        private val SUCCESS_AMPLITUDES = intArrayOf(0, 150, 0, 150)

        // Effect IDs from android.os.VibrationEffect. THUD, POP, the ringtones and
        // TEXTURE_TICK are non-public IDs whose support varies per device.
        private const val EFFECT_CLICK = 0
        private const val EFFECT_DOUBLE_CLICK = 1
        private const val EFFECT_TICK = 2
        private const val EFFECT_THUD = 3
        private const val EFFECT_POP = 4
        private const val EFFECT_HEAVY_CLICK = 5
        private const val EFFECT_RINGTONE_FIRST = 6
        private const val EFFECT_RINGTONE_LAST = 20
        private const val EFFECT_TEXTURE_TICK = 21

        @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.O)
        private fun hasOreoHaptics(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

        @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.Q)
        private fun hasPredefinedEffects(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

        @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.R)
        private fun canQueryEffectSupport(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

        @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.S)
        private fun hasVibratorManager(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

        /**
         * Converts an amplitude waveform into the `[off, on, off, on, ...]`
         * layout expected by the legacy `Vibrator.vibrate(long[], int)` API,
         * merging consecutive segments that share the same on/off state.
         *
         * @return the legacy pattern and the translated repeat index
         * (`-1` when [repeat] is `-1`).
         */
        @VisibleForTesting
        internal fun toLegacyPattern(timings: LongArray, amplitudes: IntArray, repeat: Int): Pair<LongArray, Int> {
            val pattern = ArrayList<Long>(timings.size + 1)
            val slotOf = IntArray(timings.size)
            var slotOn = false // The first legacy slot is always an "off" slot.
            var accumulated = 0L
            for (i in timings.indices) {
                val on = amplitudes[i] > 0
                if (on != slotOn) {
                    pattern.add(accumulated)
                    accumulated = 0L
                    slotOn = on
                }
                slotOf[i] = pattern.size
                accumulated += timings[i]
            }
            pattern.add(accumulated)
            val legacyRepeat = if (repeat in timings.indices) slotOf[repeat] else NO_REPEAT
            return Pair(pattern.toLongArray(), legacyRepeat)
        }

        /** Approximation of a predefined effect for devices below API 29. */
        private fun predefinedFallback(effectId: Int): Pair<LongArray, IntArray> = when (effectId) {
            EFFECT_DOUBLE_CLICK -> Pair(longArrayOf(0, 20, 60, 20), intArrayOf(0, 200, 0, 200))
            EFFECT_TICK -> Pair(longArrayOf(0, 10), intArrayOf(0, 120))
            EFFECT_TEXTURE_TICK -> Pair(longArrayOf(0, 5), intArrayOf(0, 80))
            EFFECT_THUD -> Pair(longArrayOf(0, 60), intArrayOf(0, 255))
            EFFECT_POP -> Pair(longArrayOf(0, 30), intArrayOf(0, 200))
            EFFECT_HEAVY_CLICK -> Pair(longArrayOf(0, 30), intArrayOf(0, 255))
            in EFFECT_RINGTONE_FIRST..EFFECT_RINGTONE_LAST ->
                Pair(longArrayOf(0, 200, 100, 200), intArrayOf(0, 255, 0, 255))
            else -> Pair(longArrayOf(0, 20), intArrayOf(0, 200)) // EFFECT_CLICK
        }

        private fun isKnownEffect(effectId: Int): Boolean = effectId in EFFECT_CLICK..EFFECT_TEXTURE_TICK
    }

    private var channel: MethodChannel? = null

    /** The vibrator to drive, or `null` when the device has none. */
    @VisibleForTesting
    internal var vibrator: Vibrator? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        vibrator = resolveVibrator(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        // A repeating waveform would otherwise outlive the Flutter engine.
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
            // Nothing sensible to do while detaching.
        }
        vibrator = null
    }

    private fun resolveVibrator(context: Context): Vibrator? = try {
        val service = if (hasVibratorManager()) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        service?.takeIf { it.hasVibrator() }
    } catch (_: Exception) {
        null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "hasCustomHapticsSupport" -> result.success(hasCustomHapticsSupport())
            "playWaveform" -> playWaveform(call, result)
            "playPredefined" -> playPredefined(call, result)
            "playAhap" -> vibrateWaveform(AHAP_FALLBACK_TIMINGS, AHAP_FALLBACK_AMPLITUDES, NO_REPEAT, result)
            "success" -> vibrateWaveform(SUCCESS_TIMINGS, SUCCESS_AMPLITUDES, NO_REPEAT, result)
            "stop", "cancel" -> runVibration(result) { it.cancel() }
            // Player controls are Core Haptics concepts; documented as no-ops on Android.
            "pause", "resume", "seek" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun hasCustomHapticsSupport(): Boolean {
        val vib = vibrator ?: return false
        return hasOreoHaptics() && vib.hasAmplitudeControl()
    }

    private fun playWaveform(call: MethodCall, result: Result) {
        val timings = call.longArray("timings")
        val amplitudes = call.intArray("amplitudes")
        val repeat = call.int("repeat") ?: NO_REPEAT
        val problem = when {
            timings == null || amplitudes == null ->
                "'timings' and 'amplitudes' must be lists of numbers."
            timings.isEmpty() -> "'timings' must not be empty."
            timings.size != amplitudes.size ->
                "'timings' and 'amplitudes' must have the same length (got ${timings.size} and ${amplitudes.size})."
            timings.any { it < 0 } -> "'timings' must not contain negative values."
            amplitudes.any { it < 0 || it > MAX_AMPLITUDE } -> "'amplitudes' must be within 0..$MAX_AMPLITUDE."
            repeat != NO_REPEAT && repeat !in timings.indices ->
                "'repeat' must be -1 or an index into 'timings' (got $repeat)."
            else -> null
        }
        if (problem != null) {
            result.error(ERROR_INVALID_ARGS, problem, null)
            return
        }
        vibrateWaveform(timings!!, amplitudes!!, repeat, result)
    }

    private fun vibrateWaveform(timings: LongArray, amplitudes: IntArray, repeat: Int, result: Result) {
        // Nothing to play: succeed without touching the hardware (matches iOS).
        if (timings.all { it == 0L }) {
            result.success(null)
            return
        }
        runVibration(result) { vib ->
            if (hasOreoHaptics()) {
                vib.vibrate(VibrationEffect.createWaveform(timings, amplitudes, repeat))
            } else {
                val (pattern, legacyRepeat) = toLegacyPattern(timings, amplitudes, repeat)
                @Suppress("DEPRECATION")
                vib.vibrate(pattern, legacyRepeat)
            }
        }
    }

    private fun playPredefined(call: MethodCall, result: Result) {
        val effectId = call.int("effectId")
        if (effectId == null || !isKnownEffect(effectId)) {
            result.error(ERROR_INVALID_ARGS, "Unknown predefined effect id: $effectId", null)
            return
        }
        if (!hasPredefinedEffects()) {
            val (timings, amplitudes) = predefinedFallback(effectId)
            vibrateWaveform(timings, amplitudes, NO_REPEAT, result)
            return
        }
        runVibration(result) { vib ->
            val resolvedId = if (canQueryEffectSupport() &&
                vib.areAllEffectsSupported(effectId) == Vibrator.VIBRATION_EFFECT_SUPPORT_NO
            ) {
                EFFECT_CLICK
            } else {
                effectId
            }
            vib.vibrate(VibrationEffect.createPredefined(resolvedId))
        }
    }

    /**
     * Runs [block] against the vibrator and replies exactly once. A device
     * without a vibrator is a silent success; failures become errors.
     */
    private inline fun runVibration(result: Result, block: (Vibrator) -> Unit) {
        val vib = vibrator
        if (vib == null) {
            result.success(null)
            return
        }
        try {
            block(vib)
            result.success(null)
        } catch (e: SecurityException) {
            result.error(
                ERROR_PERMISSION,
                "Vibration failed. Add <uses-permission android:name=\"android.permission.VIBRATE\"/> to AndroidManifest.xml.",
                e.message
            )
        } catch (e: IllegalArgumentException) {
            result.error(ERROR_INVALID_ARGS, e.message ?: "Invalid vibration arguments.", null)
        } catch (e: Exception) {
            result.error(ERROR_VIBRATION, e.message ?: e.javaClass.simpleName, null)
        }
    }

    // --- Argument helpers -------------------------------------------------

    private fun MethodCall.arg(key: String): Any? = try {
        argument<Any?>(key)
    } catch (_: ClassCastException) {
        null
    }

    private fun MethodCall.int(key: String): Int? = (arg(key) as? Number)?.toInt()

    private fun MethodCall.numberList(key: String): List<Number>? {
        val raw = arg(key) as? List<*> ?: return null
        val numbers = ArrayList<Number>(raw.size)
        for (item in raw) {
            numbers.add(item as? Number ?: return null)
        }
        return numbers
    }

    private fun MethodCall.longArray(key: String): LongArray? =
        numberList(key)?.map { it.toLong() }?.toLongArray()

    private fun MethodCall.intArray(key: String): IntArray? =
        numberList(key)?.map { it.toInt() }?.toIntArray()
}
