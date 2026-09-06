package com.example.advanced_haptics

import android.os.Vibrator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions

/*
 * Unit tests for the Kotlin side of the plugin.
 *
 * They run on a plain JVM where `Build.VERSION.SDK_INT` is 0, so they cover the
 * argument validation, the reply contract and the pre-API-26 (legacy Vibrator
 * API) code paths. Run them with `./gradlew testDebugUnitTest` from
 * `example/android/` after building the example app once.
 */
internal class AdvancedHapticsPluginTest {

    // SystemClock is not available on the JVM, so every plugin gets a fake clock.
    private fun pluginWith(vibrator: Vibrator?): AdvancedHapticsPlugin =
        AdvancedHapticsPlugin().apply {
            this.vibrator = vibrator
            this.clock = { 1_000L }
        }

    private fun mockVibrator(): Vibrator = Mockito.mock(Vibrator::class.java)

    private fun mockResult(): MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

    private fun waveformCall(
        timings: List<Any?>?,
        amplitudes: List<Any?>?,
        repeat: Any? = null
    ): MethodCall {
        val args = HashMap<String, Any?>()
        args["timings"] = timings
        args["amplitudes"] = amplitudes
        if (repeat != null) args["repeat"] = repeat
        args["atTime"] = 0.0
        return MethodCall("playWaveform", args)
    }

    @Test
    fun unknownMethod_isReportedAsNotImplemented() {
        val result = mockResult()
        pluginWith(mockVibrator()).onMethodCall(MethodCall("getPlatformVersion", null), result)
        verify(result).notImplemented()
    }

    @Test
    fun hasCustomHapticsSupport_isFalseWithoutVibrator() {
        val result = mockResult()
        pluginWith(null).onMethodCall(MethodCall("hasCustomHapticsSupport", null), result)
        verify(result).success(false)
    }

    @Test
    fun hasCustomHapticsSupport_isFalseBelowApi26() {
        val result = mockResult()
        pluginWith(mockVibrator()).onMethodCall(MethodCall("hasCustomHapticsSupport", null), result)
        verify(result).success(false)
    }

    @Test
    fun playWaveform_withoutVibrator_succeedsQuietly() {
        val result = mockResult()
        pluginWith(null).onMethodCall(waveformCall(listOf(0, 100), listOf(0, 255)), result)
        verify(result).success(null)
    }

    @Test
    fun playWaveform_missingArguments_isInvalid() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(waveformCall(null, listOf(0, 255)), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_INVALID_ARGS), any(), any())
        verifyNoInteractions(vibrator)
    }

    @Test
    fun playWaveform_nonNumericArguments_isInvalid() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(waveformCall(listOf(0, "100"), listOf(0, 255)), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_INVALID_ARGS), any(), any())
        verifyNoInteractions(vibrator)
    }

    @Test
    fun playWaveform_mismatchedLengths_isInvalid() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(waveformCall(listOf(0, 100), listOf(0)), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_INVALID_ARGS), any(), any())
        verifyNoInteractions(vibrator)
    }

    @Test
    fun playWaveform_emptyLists_isInvalid() {
        val result = mockResult()
        pluginWith(mockVibrator()).onMethodCall(waveformCall(emptyList(), emptyList()), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_INVALID_ARGS), any(), any())
    }

    @Test
    fun playWaveform_negativeTiming_isInvalid() {
        val result = mockResult()
        pluginWith(mockVibrator()).onMethodCall(waveformCall(listOf(0, -1), listOf(0, 100)), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_INVALID_ARGS), any(), any())
    }

    @Test
    fun playWaveform_amplitudeOutOfRange_isInvalid() {
        val result = mockResult()
        pluginWith(mockVibrator()).onMethodCall(waveformCall(listOf(0, 10), listOf(0, 256)), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_INVALID_ARGS), any(), any())
    }

    @Test
    fun playWaveform_repeatOutOfRange_isInvalid() {
        val result = mockResult()
        pluginWith(mockVibrator()).onMethodCall(waveformCall(listOf(0, 10), listOf(0, 10), repeat = 2), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_INVALID_ARGS), any(), any())
    }

    @Test
    fun playWaveform_legacyFallback_playsOnOffPattern() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(
            waveformCall(listOf(0, 100, 200, 300), listOf(0, 150, 0, 255)),
            result
        )
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(0, 100, 200, 300), -1)
        verify(result).success(null)
    }

    @Test
    fun playWaveform_legacyFallback_translatesRepeatIndex() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(
            waveformCall(listOf(0, 500, 100, 50), listOf(0, 255, 0, 100), repeat = 2),
            result
        )
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(0, 500, 100, 50), 2)
        verify(result).success(null)
    }

    @Test
    fun playWaveform_acceptsLongAndDoubleNumbers() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(waveformCall(listOf(0L, 100L), listOf(0.0, 255.0)), result)
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(0, 100), -1)
        verify(result).success(null)
    }

    @Test
    fun playWaveform_allZeroTimings_doesNotVibrate() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(waveformCall(listOf(0, 0), listOf(0, 255)), result)
        verifyNoInteractions(vibrator)
        verify(result).success(null)
    }

    @Test
    fun playWaveform_securityException_isReportedNotThrown() {
        val vibrator = mockVibrator()
        @Suppress("DEPRECATION")
        Mockito.doThrow(SecurityException("no VIBRATE permission"))
            .`when`(vibrator).vibrate(any(LongArray::class.java), anyInt())
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(waveformCall(listOf(0, 100), listOf(0, 255)), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_PERMISSION), any(), any())
        verify(result, never()).success(any())
    }

    @Test
    fun playAhapAndSuccess_useFallbackPatternsBelowApi26() {
        val vibrator = mockVibrator()
        val ahapResult = mockResult()
        val successResult = mockResult()
        val plugin = pluginWith(vibrator)
        plugin.onMethodCall(MethodCall("playAhap", mapOf("path" to "a.ahap", "atTime" to 0.0)), ahapResult)
        plugin.onMethodCall(MethodCall("success", null), successResult)
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(0, 100, 50, 100), -1)
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(0, 50, 100, 50), -1)
        verify(ahapResult).success(null)
        verify(successResult).success(null)
    }

    @Test
    fun playPredefined_unknownEffect_isInvalid() {
        val result = mockResult()
        pluginWith(mockVibrator()).onMethodCall(MethodCall("playPredefined", mapOf("effectId" to 99)), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_INVALID_ARGS), any(), any())
    }

    @Test
    fun playPredefined_belowApi29_playsApproximation() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(MethodCall("playPredefined", mapOf("effectId" to 1)), result)
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(0, 20, 60, 20), -1)
        verify(result).success(null)
    }

    @Test
    fun stopAndCancel_cancelTheVibrator() {
        val vibrator = mockVibrator()
        val stopResult = mockResult()
        val cancelResult = mockResult()
        val plugin = pluginWith(vibrator)
        plugin.onMethodCall(MethodCall("stop", mapOf("atTime" to 0.0)), stopResult)
        plugin.onMethodCall(MethodCall("cancel", null), cancelResult)
        verify(vibrator, Mockito.times(2)).cancel()
        verify(stopResult).success(null)
        verify(cancelResult).success(null)
    }

    @Test
    fun playerControls_withoutPattern_arePlayerNil() {
        val vibrator = mockVibrator()
        val plugin = pluginWith(vibrator)
        for (method in listOf("pause", "resume", "seek")) {
            val result = mockResult()
            plugin.onMethodCall(MethodCall(method, mapOf("atTime" to 0.0, "offset" to 0.0)), result)
            verify(result).error(eq(AdvancedHapticsPlugin.ERROR_PLAYER_NIL), any(), any())
        }
        verifyNoInteractions(vibrator)
    }

    // --- Emulated player controls ---------------------------------------

    private class FakeClock(var nowMs: Long = 1_000L)

    private fun pluginWithClock(vibrator: Vibrator, clock: FakeClock): AdvancedHapticsPlugin =
        pluginWith(vibrator).apply { this.clock = { clock.nowMs } }

    private fun call(method: String, vararg args: Pair<String, Any?>): MethodCall =
        MethodCall(method, mapOf(*args))

    @Test
    fun pause_withoutActivePattern_isPlayerNil() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(call("pause", "atTime" to 0.0), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_PLAYER_NIL), any(), any())
        verifyNoInteractions(vibrator)
    }

    @Test
    fun pause_afterNonLoopingPatternFinished_isPlayerNil() {
        val vibrator = mockVibrator()
        val clock = FakeClock()
        val plugin = pluginWithClock(vibrator, clock)
        plugin.onMethodCall(waveformCall(listOf(0, 100, 200, 300), listOf(0, 150, 0, 255)), mockResult())
        clock.nowMs += 600
        val result = mockResult()
        plugin.onMethodCall(call("pause", "atTime" to 0.0), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_PLAYER_NIL), any(), any())
        verify(vibrator, never()).cancel()
    }

    @Test
    fun pauseThenResume_replaysRemainderOfPattern() {
        val vibrator = mockVibrator()
        val clock = FakeClock()
        val plugin = pluginWithClock(vibrator, clock)
        plugin.onMethodCall(waveformCall(listOf(0, 100, 200, 300), listOf(0, 150, 0, 255)), mockResult())
        clock.nowMs += 150

        val pauseResult = mockResult()
        plugin.onMethodCall(call("pause", "atTime" to 0.0), pauseResult)
        verify(vibrator).cancel()
        verify(pauseResult).success(null)

        clock.nowMs += 5_000 // Time passes while paused; the position must not advance.
        val resumeResult = mockResult()
        plugin.onMethodCall(call("resume", "atTime" to 0.0), resumeResult)
        // 150 ms into the pattern: 150 ms of the 200 ms pause remain, then the 300 ms buzz.
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(150, 300), -1)
        verify(resumeResult).success(null)
    }

    @Test
    fun resume_whenNotPaused_isNoOp() {
        val vibrator = mockVibrator()
        val clock = FakeClock()
        val plugin = pluginWithClock(vibrator, clock)
        plugin.onMethodCall(waveformCall(listOf(0, 100, 200, 300), listOf(0, 150, 0, 255)), mockResult())
        clock.nowMs += 50
        val result = mockResult()
        plugin.onMethodCall(call("resume", "atTime" to 0.0), result)
        verify(result).success(null)
        @Suppress("DEPRECATION")
        verify(vibrator, Mockito.times(1)).vibrate(any(LongArray::class.java), anyInt())
        verify(vibrator, never()).cancel()
    }

    @Test
    fun seek_whilePlaying_restartsFromOffset() {
        val vibrator = mockVibrator()
        val clock = FakeClock()
        val plugin = pluginWithClock(vibrator, clock)
        plugin.onMethodCall(waveformCall(listOf(0, 100, 200, 300), listOf(0, 150, 0, 255)), mockResult())
        clock.nowMs += 20
        val result = mockResult()
        plugin.onMethodCall(call("seek", "offset" to 0.25), result)
        verify(vibrator).cancel()
        // 250 ms in: 50 ms of the pause remain, then the 300 ms buzz.
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(50, 300), -1)
        verify(result).success(null)
    }

    @Test
    fun seek_pastEndOfNonLoopingPattern_endsPlayback() {
        val vibrator = mockVibrator()
        val clock = FakeClock()
        val plugin = pluginWithClock(vibrator, clock)
        plugin.onMethodCall(waveformCall(listOf(0, 100), listOf(0, 255)), mockResult())
        plugin.onMethodCall(call("seek", "offset" to 5.0), mockResult())
        verify(vibrator).cancel()
        val result = mockResult()
        plugin.onMethodCall(call("pause", "atTime" to 0.0), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_PLAYER_NIL), any(), any())
    }

    @Test
    fun seek_whilePaused_onlyMovesPosition() {
        val vibrator = mockVibrator()
        val clock = FakeClock()
        val plugin = pluginWithClock(vibrator, clock)
        plugin.onMethodCall(waveformCall(listOf(0, 100, 200, 300), listOf(0, 150, 0, 255)), mockResult())
        plugin.onMethodCall(call("pause", "atTime" to 0.0), mockResult())
        plugin.onMethodCall(call("seek", "offset" to 0.4), mockResult())
        plugin.onMethodCall(call("resume", "atTime" to 0.0), mockResult())
        // Resumed at 400 ms: 200 ms of the final buzz remain.
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(0, 200), -1)
    }

    @Test
    fun pauseThenResume_loopingPattern_wrapsPositionAndKeepsLooping() {
        val vibrator = mockVibrator()
        val clock = FakeClock()
        val plugin = pluginWithClock(vibrator, clock)
        // 400 ms buzz, then loop [150 off, 40 on] forever.
        plugin.onMethodCall(
            waveformCall(listOf(0, 400, 150, 40), listOf(0, 255, 0, 160), repeat = 2),
            mockResult()
        )
        clock.nowMs += 400 + 190 + 50 // One full loop pass plus 50 ms into the next.
        plugin.onMethodCall(call("pause", "atTime" to 0.0), mockResult())
        plugin.onMethodCall(call("resume", "atTime" to 0.0), mockResult())
        // 100 ms of the pause remain, the 40 ms tick, then the full loop body repeats from index 2.
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(100, 40, 150, 40), 2)
    }

    @Test
    fun stop_clearsPlayerState() {
        val vibrator = mockVibrator()
        val clock = FakeClock()
        val plugin = pluginWithClock(vibrator, clock)
        plugin.onMethodCall(waveformCall(listOf(0, 100, 200, 300), listOf(0, 150, 0, 255)), mockResult())
        plugin.onMethodCall(call("stop", "atTime" to 0.0), mockResult())
        val result = mockResult()
        plugin.onMethodCall(call("resume", "atTime" to 0.0), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_PLAYER_NIL), any(), any())
    }

    @Test
    fun waveform_positionAt_wrapsInsideLoop() {
        val wave = AdvancedHapticsPlugin.Waveform(longArrayOf(0, 400, 150, 40), intArrayOf(0, 255, 0, 160), 2)
        assertEquals(400L, wave.introMs)
        assertEquals(190L, wave.loopMs)
        assertEquals(50L, wave.positionAt(50))
        assertEquals(400L, wave.positionAt(590))
        assertEquals(450L, wave.positionAt(640))
    }

    @Test
    fun waveform_positionAt_isNullAfterNonLoopingEnd() {
        val wave = AdvancedHapticsPlugin.Waveform(longArrayOf(0, 100), intArrayOf(0, 255), -1)
        assertEquals(100L, wave.totalMs)
        assertEquals(null, wave.positionAt(100))
        assertEquals(99L, wave.positionAt(99))
    }

    @Test
    fun waveform_sliceFrom_insideIntroKeepsLoopIndex() {
        val wave = AdvancedHapticsPlugin.Waveform(longArrayOf(0, 400, 150, 40), intArrayOf(0, 255, 0, 160), 2)
        val slice = wave.sliceFrom(100)!!
        assertContentEquals(longArrayOf(300, 150, 40), slice.timings)
        assertContentEquals(intArrayOf(255, 0, 160), slice.amplitudes)
        assertEquals(1, slice.repeat)
    }

    // --- Patterns and compositions ----------------------------------------

    private fun patternCall(
        events: List<Map<String, Any?>>?,
        timings: List<Any?>? = listOf(30, 70, 30),
        amplitudes: List<Any?>? = listOf(255, 0, 255)
    ): MethodCall = MethodCall(
        "playPattern",
        mapOf("events" to events, "timings" to timings, "amplitudes" to amplitudes, "atTime" to 0.0)
    )

    private val twoTaps = listOf(
        mapOf("type" to "transient", "time" to 0.0, "intensity" to 1.0, "sharpness" to 0.5),
        mapOf("type" to "transient", "time" to 0.1, "intensity" to 1.0, "sharpness" to 0.5)
    )

    @Test
    fun playPattern_belowApi30_playsFlattenedWaveform() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(patternCall(twoTaps), result)
        // Legacy patterns always start with an "off" slot.
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(0, 30, 70, 30), -1)
        verify(result).success(null)
    }

    @Test
    fun playPattern_withBadWaveform_isInvalid() {
        val vibrator = mockVibrator()
        val result = mockResult()
        pluginWith(vibrator).onMethodCall(patternCall(twoTaps, timings = listOf(30), amplitudes = listOf(255, 0)), result)
        verify(result).error(eq(AdvancedHapticsPlugin.ERROR_INVALID_ARGS), any(), any())
        verifyNoInteractions(vibrator)
    }

    @Test
    fun playPattern_isPausable() {
        val vibrator = mockVibrator()
        val clock = FakeClock()
        val plugin = pluginWithClock(vibrator, clock)
        plugin.onMethodCall(patternCall(twoTaps), mockResult())
        clock.nowMs += 50
        val result = mockResult()
        plugin.onMethodCall(call("pause", "atTime" to 0.0), result)
        verify(vibrator).cancel()
        verify(result).success(null)
    }

    @Test
    fun playComposition_belowApi30_playsFlattenedWaveform() {
        val vibrator = mockVibrator()
        val result = mockResult()
        val primitives = listOf(
            mapOf("id" to 1, "scale" to 1.0, "delayMs" to 0),
            mapOf("id" to 7, "scale" to 0.5, "delayMs" to 50)
        )
        pluginWith(vibrator).onMethodCall(
            MethodCall(
                "playComposition",
                mapOf("primitives" to primitives, "timings" to listOf(30, 50, 30), "amplitudes" to listOf(255, 0, 89))
            ),
            result
        )
        @Suppress("DEPRECATION")
        verify(vibrator).vibrate(longArrayOf(0, 30, 50, 30), -1)
        verify(result).success(null)
    }

    @Test
    fun arePrimitivesSupported_isFalseBelowApi30() {
        val result = mockResult()
        pluginWith(mockVibrator()).onMethodCall(
            MethodCall("arePrimitivesSupported", mapOf("ids" to listOf(1, 7))),
            result
        )
        verify(result).success(false)
    }

    @Test
    fun delaysFor_measuresFromPreviousPrimitiveEnd() {
        // Taps at 0, 100 and 130 ms with 30 ms primitives: the third one would
        // start before the second ends, so it follows immediately.
        val delays = AdvancedHapticsPlugin.delaysFor(
            doubleArrayOf(0.0, 100.0, 130.0, 300.0),
            intArrayOf(30, 30, 30, 30)
        )
        assertContentEquals(intArrayOf(0, 70, 0, 140), delays)
    }

    @Test
    fun primitiveFor_choosesBySharpness() {
        assertEquals(AdvancedHapticsPlugin.PRIMITIVE_TICK, AdvancedHapticsPlugin.primitiveFor(0.9f, extended = true))
        assertEquals(AdvancedHapticsPlugin.PRIMITIVE_CLICK, AdvancedHapticsPlugin.primitiveFor(0.5f, extended = true))
        assertEquals(AdvancedHapticsPlugin.PRIMITIVE_THUD, AdvancedHapticsPlugin.primitiveFor(0.1f, extended = true))
        // THUD needs API 31; fall back to CLICK on API 30.
        assertEquals(AdvancedHapticsPlugin.PRIMITIVE_CLICK, AdvancedHapticsPlugin.primitiveFor(0.1f, extended = false))
    }

    @Test
    fun toLegacyPattern_mergesSegmentsAndKeepsLeadingOff() {
        val (pattern, repeat) = AdvancedHapticsPlugin.toLegacyPattern(
            longArrayOf(50, 50, 100, 30, 30),
            intArrayOf(200, 200, 0, 0, 90),
            -1
        )
        assertContentEquals(longArrayOf(0, 100, 130, 30), pattern)
        assertEquals(-1, repeat)
    }

    @Test
    fun toLegacyPattern_mapsRepeatIntoMergedSlot() {
        val (pattern, repeat) = AdvancedHapticsPlugin.toLegacyPattern(
            longArrayOf(0, 100, 100, 50),
            intArrayOf(0, 200, 200, 0),
            2
        )
        assertContentEquals(longArrayOf(0, 200, 50), pattern)
        assertEquals(1, repeat)
    }
}
