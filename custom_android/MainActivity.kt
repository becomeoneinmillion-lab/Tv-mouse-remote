package com.example.tvremote

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.tvremote/input"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val service = MouseAccessibilityService.instance
            when (call.method) {
                "moveCursor" -> {
                    val dx = call.argument<Double>("dx")?.toFloat() ?: 0f
                    val dy = call.argument<Double>("dy")?.toFloat() ?: 0f
                    service?.moveCursor(dx, dy)
                    result.success(null)
                }
                "clickCursor" -> {
                    service?.clickAtCursor()
                    result.success(null)
                }
                "scrollCursor" -> {
                    val dy = call.argument<Double>("dy")?.toFloat() ?: 0f
                    service?.scrollAtCursor(dy)
                    result.success(null)
                }
                "sendText" -> {
                    val text = call.argument<String>("text") ?: ""
                    service?.injectText(text)
                    result.success(null)
                }
                "pressBack" -> {
                    service?.pressGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
                    result.success(null)
                }
                "pressHome" -> {
                    service?.pressGlobal(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME)
                    result.success(null)
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
