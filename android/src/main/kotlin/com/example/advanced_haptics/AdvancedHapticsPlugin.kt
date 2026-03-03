package com.example.advanced_haptics

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class AdvancedHapticsPlugin: FlutterPlugin, MethodCallHandler {

    companion object {
        private const val MIN_SDK_OREO = Build.VERSION_CODES.O // 26
    }

    private fun hasOreoHaptics(): Boolean = Build.VERSION.SDK_INT >= MIN_SDK_OREO

    private lateinit var channel: MethodChannel
    private var vibrator: Vibrator? = null
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.example/advanced_haptics")
        channel.setMethodCallHandler(this)
        vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator?
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "hasCustomHapticsSupport" -> {
                val hasSupport = if (hasOreoHaptics()) {
                    vibrator?.hasAmplitudeControl() ?: false
                } else false
                result.success(hasSupport)
            }

            "playWaveform" -> {
                if (hasOreoHaptics()) {
                    val timings = call.argument<ArrayList<Int>>("timings")?.map { it.toLong() }?.toLongArray()
                    val amplitudes = call.argument<ArrayList<Int>>("amplitudes")?.toIntArray()
                    val repeat = call.argument<Int>("repeat") ?: -1

                    if (timings != null && amplitudes != null && timings.size == amplitudes.size) {
                        try {
                            val effect = VibrationEffect.createWaveform(timings, amplitudes, repeat)
                            vibrator?.vibrate(effect)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("VIBRATION_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Timings and amplitudes must not be null and must be equal length", null)
                    }
                } else {
                    vibrator?.vibrate(200)
                    result.success(null)
                }
            }

            "playPredefined" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val effectId = call.argument<Int>("effectId") ?: VibrationEffect.EFFECT_CLICK
                    try {
                        val effect = VibrationEffect.createPredefined(effectId)
                        vibrator?.vibrate(effect)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("PREDEFINED_ERROR", e.message, null)
                    }
                } else {
                    result.error("UNSUPPORTED_API", "Predefined effects require Android API 29+", null)
                }
            }

            "playAhap" -> {
                // Fallback implementation for Android
                if (hasOreoHaptics()) {
                    val effect = VibrationEffect.createWaveform(
                        longArrayOf(0, 100, 50, 100),
                        intArrayOf(0, 255, 0, 150),
                        -1
                    )
                    vibrator?.vibrate(effect)
                } else {
                    vibrator?.vibrate(200)
                }
                result.success(null)
            }

            "success" -> {
                if (hasOreoHaptics()) {
                    val effect = VibrationEffect.createWaveform(
                        longArrayOf(0, 50, 100, 50),
                        intArrayOf(0, 150, 0, 150),
                        -1
                    )
                    vibrator?.vibrate(effect)
                } else {
                    vibrator?.vibrate(longArrayOf(0, 50, 100, 50), -1)
                }
                result.success(null)
            }

            "stop" -> {
                vibrator?.cancel()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        vibrator = null
    }
}
