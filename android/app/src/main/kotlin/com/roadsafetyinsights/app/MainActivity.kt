package com.roadsafetyinsights.app

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Log
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Navigation is running, so leaving the app should float it. */
    private var autoPictureInPicture = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // Back during navigation floats the app (or hides it)
                    // instead of closing it, so the trip keeps running.
                    "moveToBackground" -> result.success(leaveWithoutClosing())
                    "setAutoPictureInPicture" -> {
                        autoPictureInPicture = call.argument<Boolean>("enabled") == true
                        result.success(updatePictureInPictureParams())
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Android 8 to 11 cannot enter picture-in-picture automatically, so do
    // it when the user leaves with home or recents.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPictureInPicture && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            enterPictureInPicture()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pictureInPictureChanged", isInPictureInPictureMode)
    }

    private fun leaveWithoutClosing(): Boolean {
        if (autoPictureInPicture && enterPictureInPicture()) return true
        return moveTaskToBack(true)
    }

    /** On Android 12+ the system floats the app by itself when it is left. */
    private fun updatePictureInPictureParams(): Boolean {
        if (!supportsPictureInPicture()) return false
        return runCatching { setPictureInPictureParams(pictureInPictureParams()) }
            .onFailure { Log.w(TAG, "Could not update picture-in-picture", it) }
            .isSuccess
    }

    private fun enterPictureInPicture(): Boolean {
        if (!supportsPictureInPicture()) return false
        return runCatching { enterPictureInPictureMode(pictureInPictureParams()) }
            .onFailure { Log.w(TAG, "Could not enter picture-in-picture", it) }
            .getOrDefault(false)
    }

    private fun pictureInPictureParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(PIP_WIDTH, PIP_HEIGHT))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoPictureInPicture)
            // The map redraws itself; stretching the old frame looks broken.
            builder.setSeamlessResizeEnabled(false)
        }

        return builder.build()
    }

    private fun supportsPictureInPicture(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private companion object {
        const val CHANNEL = "com.roadsafetyinsights.app/window"
        const val TAG = "RSI"

        // Portrait window: guidance on top, road ahead below.
        const val PIP_WIDTH = 3
        const val PIP_HEIGHT = 4
    }
}
