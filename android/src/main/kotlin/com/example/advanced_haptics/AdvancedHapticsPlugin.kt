package com.example.advanced_haptics

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.annotation.ChecksSdkIntAtLeast
import androidx.annotation.RequiresApi
import androidx.annotation.VisibleForTesting
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.math.roundToInt

/**
 * Android implementation of the `advanced_haptics` plugin.
 *
 * Every vibration call is guarded: a device without a vibrator silently
 * succeeds, a missing `VIBRATE` permission or an invalid effect is reported as
 * a `PlatformException` with a descriptive code, and nothing here can crash
 * the host app. Amplitude control needs API 26; older devices play the on/off
 * shape of the pattern through the legacy `Vibrator` API.
 *
 * `Vibrator` has no notion of pausing, so the Core Haptics style player
 * controls are emulated: the plugin remembers the waveform that is playing and
 * when it started, cancels the vibrator on pause, and replays the remainder of
 * the pattern (honouring `repeat`) on resume or seek.
 */
class AdvancedHapticsPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.example/advanced_haptics"

        const val ERROR_INVALID_ARGS = "INVALID_ARGS"
        const val ERROR_VIBRATION = "VIBRATION_ERROR"
        const val ERROR_PERMISSION = "PERMISSION_DENIED"
        const val ERROR_PLAYER_NIL = "PLAYER_NIL"
        private const val NO_PLAYER_MESSAGE = "No haptic pattern is currently playing."

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

        // VibrationEffect.Composition primitive IDs (API 30). THUD, SPIN and
        // LOW_TICK were made public in API 31.
        internal const val PRIMITIVE_CLICK = 1
        internal const val PRIMITIVE_THUD = 2
        internal const val PRIMITIVE_SPIN = 3
        internal const val PRIMITIVE_QUICK_RISE = 4
        internal const val PRIMITIVE_SLOW_RISE = 5
        internal const val PRIMITIVE_QUICK_FALL = 6
        internal const val PRIMITIVE_TICK = 7
        internal const val PRIMITIVE_LOW_TICK = 8

        @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.R)
        private fun hasPrimitives(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

        @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.S)
        private fun hasExtendedPrimitives(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

        private fun primitiveAvailable(id: Int): Boolean = when (id) {
            PRIMITIVE_CLICK, PRIMITIVE_QUICK_RISE, PRIMITIVE_SLOW_RISE, PRIMITIVE_QUICK_FALL, PRIMITIVE_TICK ->
                hasPrimitives()
            PRIMITIVE_THUD, PRIMITIVE_SPIN, PRIMITIVE_LOW_TICK -> hasExtendedPrimitives()
            else -> false
        }

        /** Picks the primitive whose feel is closest to a transient's sharpness. */
        internal fun primitiveFor(sharpness: Float, extended: Boolean): Int = when {
            sharpness < 0.35f && extended -> PRIMITIVE_THUD
            sharpness > 0.7f -> PRIMITIVE_TICK
            else -> PRIMITIVE_CLICK
        }

        /** Approximate primitive lengths, used when the device cannot report them (API 30). */
        internal fun nominalPrimitiveDurationMs(id: Int): Int = when (id) {
            PRIMITIVE_THUD -> 60
            PRIMITIVE_SPIN, PRIMITIVE_QUICK_RISE -> 150
            PRIMITIVE_SLOW_RISE -> 500
            PRIMITIVE_QUICK_FALL -> 100
            PRIMITIVE_TICK, PRIMITIVE_LOW_TICK -> 20
            else -> 30 // PRIMITIVE_CLICK
        }

        /**
         * Converts absolute start times into composition delays, which Android
         * measures from the end of the previous primitive. A primitive that
         * would have to start before the previous one ends starts right after it.
         */
        internal fun delaysFor(startsMs: DoubleArray, durationsMs: IntArray): IntArray {
            val delays = IntArray(startsMs.size)
            var previousEnd = 0.0
            for (i in startsMs.indices) {
                val delay = (startsMs[i] - previousEnd).roundToInt().coerceAtLeast(0)
                delays[i] = delay
                previousEnd += delay + durationsMs[i]
            }
            return delays
        }

        /** Validates waveform arguments; returns a message describing the problem or `null`. */
        internal fun validateWaveformArgs(timings: LongArray?, amplitudes: IntArray?, repeat: Int): String? = when {
            timings == null || amplitudes == null -> "'timings' and 'amplitudes' must be lists of numbers."
            timings.isEmpty() -> "'timings' must not be empty."
            timings.size != amplitudes.size ->
                "'timings' and 'amplitudes' must have the same length (got ${timings.size} and ${amplitudes.size})."
            timings.any { it < 0 } -> "'timings' must not contain negative values."
            amplitudes.any { it < 0 || it > MAX_AMPLITUDE } -> "'amplitudes' must be within 0..$MAX_AMPLITUDE."
            repeat != NO_REPEAT && repeat !in timings.indices ->
                "'repeat' must be -1 or an index into 'timings' (got $repeat)."
            else -> null
        }
    }

    /** One `addPrimitive` call of a composition. */
    internal class Primitive(val id: Int, val scale: Float, val delayMs: Int)

    /** One event of a cross-platform pattern, times in milliseconds. */
    internal class PatternEvent(
        val transient: Boolean,
        val timeMs: Double,
        val durationMs: Double,
        val intensity: Float,
        val sharpness: Float
    )

    /**
     * A waveform plus the arithmetic needed to pause, resume and seek it.
     */
    internal class Waveform(val timings: LongArray, val amplitudes: IntArray, val repeat: Int) {
        val totalMs: Long = timings.sum()
        private val loopsFromIndex: Boolean = repeat in timings.indices
        val introMs: Long = if (loopsFromIndex) timings.take(repeat).sum() else totalMs
        val loopMs: Long = if (loopsFromIndex) totalMs - introMs else 0L
        val loops: Boolean = loopsFromIndex && loopMs > 0

        /**
         * Maps an elapsed play time onto a position inside the pattern,
         * wrapping around the loop. Returns `null` once a non-looping
         * pattern has finished.
         */
        fun positionAt(elapsedMs: Long): Long? {
            val elapsed = elapsedMs.coerceAtLeast(0)
            if (elapsed < totalMs) return elapsed
            if (!loops) return null
            return introMs + (elapsed - introMs) % loopMs
        }

        /**
         * The part of the pattern that remains after [offsetMs], including
         * the loop when the pattern repeats. Returns `null` when nothing
         * remains.
         */
        fun sliceFrom(offsetMs: Long): Waveform? {
            val position = positionAt(offsetMs) ?: return null
            // Find the segment containing the position and how much of it is left.
            var index = 0
            var accumulated = 0L
            while (index < timings.size && position >= accumulated + timings[index]) {
                accumulated += timings[index]
                index++
            }
            if (index >= timings.size) return null
            val partial = accumulated + timings[index] - position

            val newTimings = ArrayList<Long>()
            val newAmplitudes = ArrayList<Int>()
            newTimings.add(partial)
            newAmplitudes.add(amplitudes[index])
            for (i in index + 1 until timings.size) {
                newTimings.add(timings[i])
                newAmplitudes.add(amplitudes[i])
            }
            var newRepeat = NO_REPEAT
            if (loops) {
                if (index < repeat) {
                    // Still in the intro: the loop segments are already appended.
                    newRepeat = 1 + (repeat - (index + 1))
                } else {
                    // Inside the loop: finish this pass, then loop the full loop body.
                    newRepeat = newTimings.size
                    for (i in repeat until timings.size) {
                        newTimings.add(timings[i])
                        newAmplitudes.add(amplitudes[i])
                    }
                }
            }
            return Waveform(newTimings.toLongArray(), newAmplitudes.toIntArray(), newRepeat)
        }
    }

    private var channel: MethodChannel? = null

    /** The vibrator to drive, or `null` when the device has none. */
    @VisibleForTesting
    internal var vibrator: Vibrator? = null

    /** Monotonic clock in milliseconds; replaceable in unit tests. */
    @VisibleForTesting
    internal var clock: () -> Long = { SystemClock.uptimeMillis() }

    // --- Emulated player state ---------------------------------------------
    private var active: Waveform? = null
    /** [clock] value when the current run of [active] started. */
    private var runStartMs = 0L
    /** Position inside [active] at which the current run started. */
    private var runOffsetMs = 0L
    /** Position inside [active] while paused, `null` while playing. */
    private var pausedAtMs: Long? = null

    private val handler: Handler by lazy { Handler(Looper.getMainLooper()) }
    private val scheduled = ArrayList<Runnable>()

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
        clearScheduled()
        active = null
        pausedAtMs = null
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
            "playPattern" -> playPattern(call, result)
            "playComposition" -> playComposition(call, result)
            "arePrimitivesSupported" -> result.success(arePrimitivesSupported(call.intList("ids")))
            "playPredefined" -> playPredefined(call, result)
            "playAhap" -> vibrateWaveform(AHAP_FALLBACK_TIMINGS, AHAP_FALLBACK_AMPLITUDES, NO_REPEAT, result)
            "success" -> vibrateWaveform(SUCCESS_TIMINGS, SUCCESS_AMPLITUDES, NO_REPEAT, result)
            "stop" -> stop(call.delayMs("atTime"), result)
            "cancel" -> stop(0L, result)
            "pause" -> playerControl(result, call.delayMs("atTime")) { pauseNow(it) }
            "resume" -> playerControl(result, call.delayMs("atTime")) { resumeNow(it) }
            "seek" -> {
                val offsetMs = call.delayMs("offset")
                playerControl(result, 0L) { seekNow(it, offsetMs) }
            }
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
        val problem = validateWaveformArgs(timings, amplitudes, repeat)
        if (problem != null) {
            result.error(ERROR_INVALID_ARGS, problem, null)
            return
        }
        vibrateWaveform(timings!!, amplitudes!!, repeat, result)
    }

    /**
     * Plays a cross-platform pattern. A transient-only pattern becomes a
     * `VibrationEffect.Composition` on API 30+ when the device supports the
     * primitives; everything else plays the pre-flattened waveform.
     */
    private fun playPattern(call: MethodCall, result: Result) {
        val timings = call.longArray("timings")
        val amplitudes = call.intArray("amplitudes")
        val problem = validateWaveformArgs(timings, amplitudes, NO_REPEAT)
        if (problem != null) {
            result.error(ERROR_INVALID_ARGS, problem, null)
            return
        }
        val events = call.events("events")
        if (hasPrimitives() && events != null) {
            val effect = composeTransients(events)
            if (effect != null) {
                vibrateEffect(effect, result)
                return
            }
        }
        vibrateWaveform(timings!!, amplitudes!!, NO_REPEAT, result)
    }

    /** Plays explicit composition primitives, falling back to the flattened waveform. */
    private fun playComposition(call: MethodCall, result: Result) {
        val timings = call.longArray("timings")
        val amplitudes = call.intArray("amplitudes")
        val problem = validateWaveformArgs(timings, amplitudes, NO_REPEAT)
        if (problem != null) {
            result.error(ERROR_INVALID_ARGS, problem, null)
            return
        }
        val primitives = call.primitives("primitives")
        if (hasPrimitives() && primitives != null) {
            val vib = vibrator
            val effect = if (vib != null) composeIfSupported(vib, primitives) else null
            if (effect != null) {
                vibrateEffect(effect, result)
                return
            }
        }
        vibrateWaveform(timings!!, amplitudes!!, NO_REPEAT, result)
    }

    private fun arePrimitivesSupported(ids: List<Int>?): Boolean {
        val vib = vibrator ?: return false
        if (!hasPrimitives() || ids.isNullOrEmpty()) return false
        if (ids.any { !primitiveAvailable(it) }) return false
        return try {
            vib.areAllPrimitivesSupported(*ids.toIntArray())
        } catch (_: Exception) {
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun composeTransients(events: List<PatternEvent>): VibrationEffect? {
        val vib = vibrator ?: return null
        if (events.isEmpty() || events.any { !it.transient }) return null
        val sorted = events.sortedBy { it.timeMs }
        val extended = hasExtendedPrimitives()
        val ids = IntArray(sorted.size) { primitiveFor(sorted[it].sharpness, extended) }
        val durations = primitiveDurations(vib, ids) ?: return null
        val delays = delaysFor(DoubleArray(sorted.size) { sorted[it].timeMs }, durations)
        val primitives = List(sorted.size) { Primitive(ids[it], sorted[it].intensity, delays[it]) }
        return composeIfSupported(vib, primitives)
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun primitiveDurations(vib: Vibrator, ids: IntArray): IntArray? = try {
        if (hasExtendedPrimitives()) {
            val reported = vib.getPrimitiveDurations(*ids)
            IntArray(ids.size) { if (reported[it] > 0) reported[it] else nominalPrimitiveDurationMs(ids[it]) }
        } else {
            IntArray(ids.size) { nominalPrimitiveDurationMs(ids[it]) }
        }
    } catch (_: Exception) {
        null
    }

    /** Builds the composition, or returns `null` when the device cannot play all of it. */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun composeIfSupported(vib: Vibrator, primitives: List<Primitive>): VibrationEffect? {
        if (primitives.isEmpty() || primitives.any { !primitiveAvailable(it.id) }) return null
        return try {
            val ids = primitives.map { it.id }.distinct().toIntArray()
            if (!vib.areAllPrimitivesSupported(*ids)) return null
            val composition = VibrationEffect.startComposition()
            for (p in primitives) {
                composition.addPrimitive(p.id, p.scale.coerceIn(0f, 1f), p.delayMs.coerceAtLeast(0))
            }
            composition.compose()
        } catch (_: Exception) {
            null
        }
    }

    /** Plays a ready-made effect; compositions and predefined effects cannot be paused. */
    private fun vibrateEffect(effect: VibrationEffect, result: Result) {
        clearScheduled()
        active = null
        pausedAtMs = null
        runVibration(result) { it.vibrate(effect) }
    }

    private fun vibrateWaveform(timings: LongArray, amplitudes: IntArray, repeat: Int, result: Result) {
        clearScheduled()
        active = null
        pausedAtMs = null
        // Nothing to play: succeed without touching the hardware (matches iOS).
        if (timings.all { it == 0L }) {
            result.success(null)
            return
        }
        val wave = Waveform(timings, amplitudes, repeat)
        runVibration(result) { vib ->
            vibrateRaw(vib, wave)
            active = wave
            runStartMs = clock()
            runOffsetMs = 0L
        }
    }

    /** Sends [wave] to the hardware without touching the player state. */
    private fun vibrateRaw(vib: Vibrator, wave: Waveform) {
        if (hasOreoHaptics()) {
            vib.vibrate(VibrationEffect.createWaveform(wave.timings, wave.amplitudes, wave.repeat))
        } else {
            val (pattern, legacyRepeat) = toLegacyPattern(wave.timings, wave.amplitudes, wave.repeat)
            @Suppress("DEPRECATION")
            vib.vibrate(pattern, legacyRepeat)
        }
    }

    // --- Emulated player controls ------------------------------------------

    /** The current position inside [active], or `null` when nothing is playing or paused. */
    private fun currentPosition(): Long? {
        val wave = active ?: return null
        pausedAtMs?.let { return it }
        val position = wave.positionAt(runOffsetMs + (clock() - runStartMs))
        if (position == null) {
            // A non-looping pattern has run to completion.
            active = null
        }
        return position
    }

    /**
     * Validates that a pattern is active, then runs [action] now or after
     * [delayMs]. A delayed action replies immediately and runs best-effort.
     */
    private fun playerControl(result: Result, delayMs: Long, action: (Vibrator) -> Unit) {
        if (currentPosition() == null) {
            result.error(ERROR_PLAYER_NIL, NO_PLAYER_MESSAGE, null)
            return
        }
        if (delayMs <= 0) {
            runVibration(result) { action(it) }
            return
        }
        schedule(delayMs) {
            val vib = vibrator ?: return@schedule
            try {
                action(vib)
            } catch (_: Exception) {
                // Scheduled controls are best-effort; the reply was already sent.
            }
        }
        result.success(null)
    }

    private fun pauseNow(vib: Vibrator) {
        if (pausedAtMs != null) return // Already paused.
        val position = currentPosition() ?: return
        pausedAtMs = position
        vib.cancel()
    }

    private fun resumeNow(vib: Vibrator) {
        val wave = active ?: return
        val position = pausedAtMs ?: return // Not paused: nothing to do.
        val remainder = wave.sliceFrom(position)
        if (remainder == null) {
            active = null
            pausedAtMs = null
            return
        }
        vibrateRaw(vib, remainder)
        runStartMs = clock()
        runOffsetMs = position
        pausedAtMs = null
    }

    private fun seekNow(vib: Vibrator, offsetMs: Long) {
        val wave = active ?: return
        val position = wave.positionAt(offsetMs)
        if (position == null) {
            // Seeking past the end of a non-looping pattern ends it.
            vib.cancel()
            active = null
            pausedAtMs = null
            return
        }
        if (pausedAtMs != null) {
            pausedAtMs = position
            return
        }
        vib.cancel()
        val remainder = wave.sliceFrom(position)
        if (remainder == null) {
            active = null
            return
        }
        vibrateRaw(vib, remainder)
        runStartMs = clock()
        runOffsetMs = position
    }

    private fun stop(delayMs: Long, result: Result) {
        if (delayMs > 0) {
            schedule(delayMs) { stopNow() }
            result.success(null)
            return
        }
        clearScheduled()
        active = null
        pausedAtMs = null
        runVibration(result) { it.cancel() }
    }

    private fun stopNow() {
        clearScheduled()
        active = null
        pausedAtMs = null
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
            // Best-effort; the reply was already sent.
        }
    }

    private fun schedule(delayMs: Long, action: () -> Unit) {
        val runnable = object : Runnable {
            override fun run() {
                scheduled.remove(this)
                action()
            }
        }
        scheduled.add(runnable)
        handler.postDelayed(runnable, delayMs)
    }

    private fun clearScheduled() {
        if (scheduled.isEmpty()) return
        for (runnable in scheduled) {
            handler.removeCallbacks(runnable)
        }
        scheduled.clear()
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

    /** Reads a duration given in seconds as non-negative milliseconds (0 when absent or invalid). */
    private fun MethodCall.delayMs(key: String): Long {
        val seconds = (arg(key) as? Number)?.toDouble() ?: return 0L
        if (seconds.isNaN() || seconds.isInfinite() || seconds <= 0) return 0L
        return (seconds * 1000).toLong()
    }

    private fun MethodCall.numberList(key: String): List<Number>? {
        val raw = arg(key) as? List<*> ?: return null
        val numbers = ArrayList<Number>(raw.size)
        for (item in raw) {
            numbers.add(item as? Number ?: return null)
        }
        return numbers
    }

    private fun MethodCall.intList(key: String): List<Int>? = numberList(key)?.map { it.toInt() }

    private fun MethodCall.events(key: String): List<PatternEvent>? {
        val raw = arg(key) as? List<*> ?: return null
        val events = ArrayList<PatternEvent>(raw.size)
        for (item in raw) {
            val map = item as? Map<*, *> ?: return null
            val type = map["type"] as? String ?: return null
            val timeMs = ((map["time"] as? Number)?.toDouble() ?: 0.0) * 1000.0
            val durationMs = ((map["duration"] as? Number)?.toDouble() ?: 0.0) * 1000.0
            val intensity = ((map["intensity"] as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
            val sharpness = ((map["sharpness"] as? Number)?.toFloat() ?: 0.5f).coerceIn(0f, 1f)
            events.add(PatternEvent(type == "transient", timeMs.coerceAtLeast(0.0), durationMs, intensity, sharpness))
        }
        return events
    }

    private fun MethodCall.primitives(key: String): List<Primitive>? {
        val raw = arg(key) as? List<*> ?: return null
        val primitives = ArrayList<Primitive>(raw.size)
        for (item in raw) {
            val map = item as? Map<*, *> ?: return null
            val id = (map["id"] as? Number)?.toInt() ?: return null
            val scale = ((map["scale"] as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f)
            val delayMs = ((map["delayMs"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
            primitives.add(Primitive(id, scale, delayMs))
        }
        return primitives
    }

    private fun MethodCall.longArray(key: String): LongArray? =
        numberList(key)?.map { it.toLong() }?.toLongArray()

    private fun MethodCall.intArray(key: String): IntArray? =
        numberList(key)?.map { it.toInt() }?.toIntArray()
}
