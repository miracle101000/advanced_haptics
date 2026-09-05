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

    private fun pluginWith(vibrator: Vibrator?): AdvancedHapticsPlugin =
        AdvancedHapticsPlugin().apply { this.vibrator = vibrator }

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
    fun playerControls_areNoOps() {
        val vibrator = mockVibrator()
        val plugin = pluginWith(vibrator)
        for (method in listOf("pause", "resume", "seek")) {
            val result = mockResult()
            plugin.onMethodCall(MethodCall(method, mapOf("atTime" to 0.0, "offset" to 0.0)), result)
            verify(result).success(null)
        }
        verifyNoInteractions(vibrator)
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
