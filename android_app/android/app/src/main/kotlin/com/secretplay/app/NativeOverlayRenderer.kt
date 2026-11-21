package com.secretplay.app

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Renders true system-level floating overlays (WindowManager TYPE_APPLICATION_OVERLAY)
 * on top of ANY app (Instagram, Telegram, Home Screen, Lock Screen) whenever the
 * partner sends a Heartbeat Pulse, Stealth Ping, Sticker Flash, or Neon Drawing.
 */
object NativeOverlayRenderer {
    private val mainHandler = Handler(Looper.getMainLooper())

    fun canDraw(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)
    }

    private fun dp(context: Context, value: Int): Int {
        return (value * context.resources.displayMetrics.density).toInt()
    }

    private fun overlayParams(touchable: Boolean, gravity: Int, yOffset: Int = 0): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        @Suppress("DEPRECATION")
        var flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON

        if (!touchable) {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            flags,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = gravity
        params.y = yOffset
        return params
    }

    private fun safeRemove(wm: WindowManager, view: View) {
        try {
            if (view.isAttachedToWindow) {
                wm.removeViewImmediate(view)
            }
        } catch (_: Exception) {}
    }

    fun showFloatingHeartbeat(context: Context): Boolean {
        if (!canDraw(context)) return false
        mainHandler.post {
            try {
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val container = LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    setPadding(dp(context, 28), dp(context, 22), dp(context, 28), dp(context, 22))
                    background = GradientDrawable(
                        GradientDrawable.Orientation.TOP_BOTTOM,
                        intArrayOf(Color.parseColor("#EAFF007A"), Color.parseColor("#D9230820"))
                    ).apply {
                        shape = GradientDrawable.OVAL
                        setStroke(dp(context, 2), Color.parseColor("#FF5CA8"))
                    }
                    elevation = 24f
                }

                val heartIcon = TextView(context).apply {
                    text = "❤️‍🔥"
                    textSize = 60f
                    gravity = Gravity.CENTER
                }
                val label = TextView(context).apply {
                    text = "تپش قلب زنده"
                    textSize = 13f
                    setTypeface(null, Typeface.BOLD)
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                }
                container.addView(heartIcon)
                container.addView(label)

                val params = overlayParams(touchable = false, gravity = Gravity.CENTER)
                wm.addView(container, params)

                val sx = ObjectAnimator.ofFloat(container, "scaleX", 0.72f, 1.25f, 0.92f, 1.20f, 1.0f)
                val sy = ObjectAnimator.ofFloat(container, "scaleY", 0.72f, 1.25f, 0.92f, 1.20f, 1.0f)
                val set = AnimatorSet().apply {
                    playTogether(sx, sy)
                    duration = 1100
                }
                set.start()
                mainHandler.postDelayed({
                    if (container.isAttachedToWindow) set.start()
                }, 1150)

                mainHandler.postDelayed({
                    container.animate().alpha(0f).setDuration(350).withEndAction {
                        safeRemove(wm, container)
                    }.start()
                }, 2400)
            } catch (_: Exception) {}
        }
        return true
    }

    fun showFloatingStealthBanner(context: Context, title: String, body: String): Boolean {
        if (!canDraw(context)) return false
        mainHandler.post {
            try {
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val pill = LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(dp(context, 20), dp(context, 12), dp(context, 20), dp(context, 12))
                    background = GradientDrawable().apply {
                        setColor(Color.parseColor("#EB111626"))
                        cornerRadius = dp(context, 22).toFloat()
                        setStroke(dp(context, 2), Color.parseColor("#00FFA3"))
                    }
                    alpha = 0f
                    elevation = 20f
                }

                val tvTitle = TextView(context).apply {
                    text = title
                    textSize = 13f
                    setTypeface(null, Typeface.BOLD)
                    setTextColor(Color.parseColor("#00FFA3"))
                }
                val tvBody = TextView(context).apply {
                    text = body
                    textSize = 12f
                    setTextColor(Color.WHITE)
                }
                pill.addView(tvTitle)
                pill.addView(tvBody)

                val params = overlayParams(
                    touchable = false,
                    gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL,
                    yOffset = dp(context, 72)
                )
                wm.addView(pill, params)
                pill.animate().alpha(1f).setDuration(250).start()

                mainHandler.postDelayed({
                    pill.animate().alpha(0f).setDuration(350).withEndAction {
                        safeRemove(wm, pill)
                    }.start()
                }, 3200)
            } catch (_: Exception) {}
        }
        return true
    }

    fun showFloatingHologram(
        context: Context,
        emoji: String,
        title: String,
        body: String,
        pngBase64: String,
        colorHex: String,
        vanishSec: Int
    ): Boolean {
        if (!canDraw(context)) return false
        mainHandler.post {
            try {
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val accent = try {
                    Color.parseColor(if (colorHex.isNotEmpty()) colorHex else "#FF007A")
                } catch (_: Exception) {
                    Color.parseColor("#FF007A")
                }

                val card = LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER_HORIZONTAL
                    setPadding(dp(context, 20), dp(context, 16), dp(context, 20), dp(context, 18))
                    background = GradientDrawable().apply {
                        setColor(Color.parseColor("#F2101322"))
                        cornerRadius = dp(context, 26).toFloat()
                        setStroke(dp(context, 2), accent)
                    }
                    elevation = 28f
                }

                var remaining = if (vanishSec > 0) vanishSec else 7
                var dismissed = false

                val topRow = LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                val timerBadge = TextView(context).apply {
                    text = "⚡ محو خودکار در ${remaining}s"
                    textSize = 12f
                    setTypeface(null, Typeface.BOLD)
                    setTextColor(accent)
                    setPadding(0, 0, dp(context, 18), 0)
                }
                val closeBtn = TextView(context).apply {
                    text = "✕"
                    textSize = 16f
                    setTypeface(null, Typeface.BOLD)
                    setTextColor(Color.WHITE)
                    setPadding(dp(context, 10), dp(context, 4), dp(context, 10), dp(context, 4))
                    background = GradientDrawable().apply {
                        setColor(Color.parseColor("#33FFFFFF"))
                        cornerRadius = dp(context, 14).toFloat()
                    }
                }
                topRow.addView(timerBadge)
                topRow.addView(closeBtn)
                card.addView(topRow)

                if (pngBase64.isNotEmpty()) {
                    try {
                        val bytes = Base64.decode(pngBase64, Base64.DEFAULT)
                        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        if (bmp != null) {
                            val imgView = ImageView(context).apply {
                                setImageBitmap(bmp)
                                adjustViewBounds = true
                                maxWidth = dp(context, 280)
                                maxHeight = dp(context, 240)
                                scaleType = ImageView.ScaleType.FIT_CENTER
                                setPadding(0, dp(context, 12), 0, dp(context, 6))
                            }
                            card.addView(imgView)
                        }
                    } catch (_: Exception) {}
                }

                if (emoji.isNotEmpty()) {
                    val emojiTv = TextView(context).apply {
                        text = emoji
                        textSize = 62f
                        gravity = Gravity.CENTER
                        setPadding(0, dp(context, 10), 0, dp(context, 4))
                    }
                    card.addView(emojiTv)
                }

                if (title.isNotEmpty()) {
                    val titleTv = TextView(context).apply {
                        text = title
                        textSize = 17f
                        setTypeface(null, Typeface.BOLD)
                        setTextColor(accent)
                        gravity = Gravity.CENTER
                        maxWidth = dp(context, 280)
                        setPadding(0, dp(context, 4), 0, dp(context, 2))
                    }
                    card.addView(titleTv)
                }

                if (body.isNotEmpty()) {
                    val bodyTv = TextView(context).apply {
                        text = body
                        textSize = 16f
                        setTypeface(null, Typeface.BOLD)
                        setTextColor(Color.WHITE)
                        gravity = Gravity.CENTER
                        maxWidth = dp(context, 280)
                        setPadding(0, dp(context, 6), 0, dp(context, 2))
                    }
                    card.addView(bodyTv)
                }

                val dismissAction = {
                    if (!dismissed) {
                        dismissed = true
                        safeRemove(wm, card)
                    }
                }
                closeBtn.setOnClickListener { dismissAction() }

                val params = overlayParams(touchable = true, gravity = Gravity.CENTER)
                wm.addView(card, params)

                val tickRunnable = object : Runnable {
                    override fun run() {
                        if (dismissed || !card.isAttachedToWindow) return
                        remaining--
                        if (remaining <= 0) {
                            dismissAction()
                        } else {
                            timerBadge.text = "⚡ محو خودکار در ${remaining}s"
                            mainHandler.postDelayed(this, 1000)
                        }
                    }
                }
                mainHandler.postDelayed(tickRunnable, 1000)
            } catch (_: Exception) {}
        }
        return true
    }
}
