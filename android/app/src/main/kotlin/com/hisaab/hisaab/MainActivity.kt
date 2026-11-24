package com.hisaab.hisaab

import android.app.Activity
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// FlutterFragmentActivity is required by local_auth (biometrics).
/// - "hisaab/privacy": turns FLAG_SECURE on/off so the app contents are hidden
///   in the recent-apps screen (and screenshots) while App lock is on.
/// - "hisaab/sound": the system ringtone picker (returns a content:// URI that
///   the notification system can play) and a short preview.
class MainActivity : FlutterFragmentActivity() {
    private var pickResult: MethodChannel.Result? = null
    private var preview: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hisaab/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val on = call.argument<Boolean>("on") == true
                    runOnUiThread {
                        if (on) {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE
                            )
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hisaab/sound")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        if (pickResult != null) {
                            result.error("busy", "Picker already open", null)
                            return@setMethodCallHandler
                        }
                        val existing = call.argument<String>("existing")
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALL)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Reminder sound")
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            if (existing != null) {
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                                    Uri.parse(existing)
                                )
                            }
                        }
                        pickResult = result
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, REQUEST_RINGTONE)
                    }
                    "preview" -> {
                        stopPreview()
                        val uriString = call.argument<String>("uri")
                        val alarm = call.argument<Boolean>("alarm") != false
                        val uri = if (uriString != null) Uri.parse(uriString)
                        else RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        val ringtone = RingtoneManager.getRingtone(this, uri)
                        if (ringtone != null) {
                            ringtone.audioAttributes = AudioAttributes.Builder()
                                .setUsage(
                                    if (alarm) AudioAttributes.USAGE_ALARM
                                    else AudioAttributes.USAGE_NOTIFICATION
                                )
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                            ringtone.play()
                            preview = ringtone
                        }
                        result.success(null)
                    }
                    "stopPreview" -> {
                        stopPreview()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun stopPreview() {
        preview?.let { if (it.isPlaying) it.stop() }
        preview = null
    }

    override fun onDestroy() {
        stopPreview()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_RINGTONE) {
            val pending = pickResult
            pickResult = null
            if (pending != null) {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                        data.getParcelableExtra(
                            RingtoneManager.EXTRA_RINGTONE_PICKED_URI,
                            Uri::class.java
                        )
                    } else {
                        data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                    }
                    if (uri == null) {
                        pending.success(null)
                    } else {
                        val title = try {
                            RingtoneManager.getRingtone(this, uri)?.getTitle(this)
                        } catch (e: Exception) {
                            null
                        }
                        pending.success(mapOf("uri" to uri.toString(), "title" to (title ?: "Ringtone")))
                    }
                } else {
                    pending.success(null)
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    companion object {
        private const val REQUEST_RINGTONE = 7711
    }
}
