package com.example.tvremote

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class MouseAccessibilityService : AccessibilityService() {

    companion object {
        var instance: MouseAccessibilityService? = null
    }

    private lateinit var windowManager: WindowManager
    private lateinit var cursorView: View
    private lateinit var params: WindowManager.LayoutParams
    private var cursorX = 400f
    private var cursorY = 300f

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        // High-visibility circular pointer (White fill with Red border)
        val dot = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.WHITE)
            setStroke(4, Color.RED)
        }

        cursorView = View(this).apply { background = dot }

        params = WindowManager.LayoutParams(
            28, 28,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = cursorX.toInt()
            y = cursorY.toInt()
        }

        windowManager.addView(cursorView, params)
    }

    fun moveCursor(dx: Float, dy: Float) {
        val dm = resources.displayMetrics
        cursorX = (cursorX + dx).coerceIn(0f, dm.widthPixels - 28f)
        cursorY = (cursorY + dy).coerceIn(0f, dm.heightPixels - 28f)
        params.x = cursorX.toInt()
        params.y = cursorY.toInt()
        cursorView.post { windowManager.updateViewLayout(cursorView, params) }
    }

    fun clickAtCursor() {
        val path = Path().apply { moveTo(cursorX + 14f, cursorY + 14f) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun scrollAtCursor(dy: Float) {
        val startY = cursorY + 14f
        val endY = (startY - dy * 3f).coerceIn(50f, resources.displayMetrics.heightPixels - 50f)
        val path = Path().apply {
            moveTo(cursorX + 14f, startY)
            lineTo(cursorX + 14f, endY)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, 120)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    fun injectText(text: String) {
        val root = rootInActiveWindow ?: return
        val focus = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focus != null) {
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            focus.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        }
    }

    fun pressGlobal(action: Int) {
        performGlobalAction(action)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        if (::cursorView.isInitialized) windowManager.removeView(cursorView)
        instance = null
    }
}
