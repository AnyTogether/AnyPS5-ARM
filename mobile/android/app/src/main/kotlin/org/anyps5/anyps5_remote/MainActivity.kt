package org.anyps5.anyps5_remote

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val vibrator: Vibrator by lazy {
        if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "org.anyps5.remote/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "name" -> result.success(deviceName())
                "rotation" -> result.success(if (rotation() == Surface.ROTATION_270) "topRight" else "topLeft")
                else -> result.notImplemented()
            }
        }
        // Remote Play's picture and sound.
        val streamChannel = MethodChannel(messenger, "org.anyps5.remote/stream")
        val player = StreamPlayer(flutterEngine.renderer, streamChannel)
        streamChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> result.success(player.open())
                "frame" -> {
                    player.frame(call.argument<ByteArray>("data") ?: ByteArray(0), call.argument<Boolean>("key") ?: false,
                        (call.argument<Number>("milliseconds") ?: 0).toLong())
                    result.success(null)
                }
                "sound" -> {
                    player.sound(call.argument<ByteArray>("data") ?: ByteArray(0))
                    result.success(null)
                }
                "close" -> {
                    player.close()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "org.anyps5.remote/haptics").setMethodCallHandler { call, result ->
            if (call.method != "set") return@setMethodCallHandler result.notImplemented()
            rumble((call.argument<Int>("strength") ?: 0).coerceIn(0, 255))
            result.success(null)
        }
    }

    override fun onPause() {
        super.onPause()
        rumble(0)
    }

    /// The game's rumble: held at `strength` until the next call, which replaces it.
    private fun rumble(strength: Int) {
        if (!vibrator.hasVibrator()) return
        if (strength == 0) return vibrator.cancel()
        if (Build.VERSION.SDK_INT >= 26) {
            val amplitude = if (vibrator.hasAmplitudeControl()) strength else VibrationEffect.DEFAULT_AMPLITUDE
            vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(1000), intArrayOf(amplitude), 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(longArrayOf(0, 1000), 0)
        }
    }

    /// ROTATION_90 is the phone turned with its top to the left, ROTATION_270 to the right.
    private fun rotation(): Int =
        if (Build.VERSION.SDK_INT >= 30) {
            display?.rotation ?: Surface.ROTATION_90
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.rotation
        }

    /// The name the user gave the phone, else its maker and model.
    private fun deviceName(): String =
        Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)?.takeIf { it.isNotBlank() }
            ?: "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"
}
