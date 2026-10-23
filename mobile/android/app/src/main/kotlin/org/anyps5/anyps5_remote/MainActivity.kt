package org.anyps5.anyps5_remote

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
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
            if (call.method == "name") result.success(deviceName()) else result.notImplemented()
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

    /// The name the user gave the phone, else its maker and model.
    private fun deviceName(): String =
        Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)?.takeIf { it.isNotBlank() }
            ?: "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"
}
