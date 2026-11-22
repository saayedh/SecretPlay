package com.secretplay.app

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Shader
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
import android.view.animation.LinearInterpolator
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Renders hardware-accelerated system-level floating overlays (TYPE_APPLICATION_OVERLAY)
 * on top of ANY app and lock screen when the partner triggers Heartbeat Pulse, Stealth Ping,
 * Animated Sticker Flash, Holographic Card, or Neon Drawing.
 */
object NativeOverlayRenderer {
    private val mainHandler = Handler(Looper.getMainLooper())

    fun canDraw(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)
    }

    private fun dp(context: Context, value: Int): Int {
        return (value * context.resources.displayMetrics.density).toInt()
    }

    private fun readPrefs(context: Context): GhostTouchNativePrefs {
        val sp = context.getSharedPreferences(StealthStandbyService.PREFS_NAME, Context.MODE_PRIVATE)
        return GhostTouchNativePrefs(
            position = sp.getString(StealthStandbyService.KEY_GT_POSITION, "center") ?: "center",
            durationSec = sp.getInt(StealthStandbyService.KEY_GT_DURATION, 7).coerceIn(3, 30),
            intensity = sp.getFloat(StealthStandbyService.KEY_GT_INTENSITY, 0.85f).coerceIn(0.2f, 1.0f),
            reducedMotion = sp.getBoolean(StealthStandbyService.KEY_GT_REDUCED_MOTION, false)
        )
    }

    private fun resolveGravityAndOffset(context: Context, position: String): Pair<Int, Int> {
        return when (position) {
            "top" -> (Gravity.TOP or Gravity.CENTER_HORIZONTAL) to dp(context, 72)
            "bottom" -> (Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL) to dp(context, 84)
            else -> Gravity.CENTER to 0
        }
    }

    private data class GhostTouchNativePrefs(
        val position: String,
        val durationSec: Int,
        val intensity: Float,
        val reducedMotion: Boolean
    )

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

    /**
     * Custom Canvas View rendering a multi-stop neon vector heart, shockwave rings,
     * and orbiting cybernetic sparks without blurry bitmaps or emoji fallbacks.
     */
    private class GlowingVectorHeartView(
        context: Context,
        private val intensity: Float,
        private val reducedMotion: Boolean
    ) : View(context) {
        private var progress = 0.25f
        private var animator: ValueAnimator? = null

        private val auraPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
        }
        private val heartFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val heartStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = Color.parseColor("#FF8EC7")
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val sparkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val heartPath = Path()

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            if (!reducedMotion && animator == null) {
                animator = ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = 1600L
                    repeatCount = ValueAnimator.INFINITE
                    interpolator = LinearInterpolator()
                    addUpdateListener {
                        progress = it.animatedValue as Float
                        invalidate()
                    }
                    start()
                }
            }
        }

        override fun onDetachedFromWindow() {
            animator?.cancel()
            animator = null
            super.onDetachedFromWindow()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val cx = width / 2f
            val cy = height / 2f
            val baseR = min(width, height) * 0.26f

            val phase = progress * (Math.PI * 2.0)
            val lub = if (progress < 0.18f) {
                sin((progress / 0.18f) * Math.PI).toFloat() * 0.16f
            } else if (progress in 0.22f..0.40f) {
                sin(((progress - 0.22f) / 0.18f) * Math.PI).toFloat() * 0.22f
            } else {
                0f
            }
            val r = baseR * (1f + if (reducedMotion) 0f else lub)

            // Ambient radial neon halo
            val auraR = baseR * (1.85f + lub)
            auraPaint.shader = RadialGradient(
                cx,
                cy,
                auraR,
                intArrayOf(
                    Color.argb((110 * intensity).toInt(), 255, 61, 154),
                    Color.argb((45 * intensity).toInt(), 180, 92, 255),
                    Color.TRANSPARENT
                ),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(cx, cy, auraR, auraPaint)

            // Expanding shockwave ring
            if (!reducedMotion) {
                val ringAlpha = ((1f - progress) * 160f * intensity).toInt().coerceIn(0, 255)
                ringPaint.color = Color.argb(ringAlpha, 0, 229, 255)
                ringPaint.strokeWidth = baseR * 0.08f
                canvas.drawCircle(cx, cy, baseR * (1.0f + progress * 0.85f), ringPaint)
            }

            // Orbiting sparks
            for (i in 0 until 6) {
                val ang = phase + i * (Math.PI / 3.0)
                val dist = baseR * 1.38f
                val sx = cx + (cos(ang) * dist).toFloat()
                val sy = cy + (sin(ang) * dist * 0.88f).toFloat()
                sparkPaint.color = if (i % 2 == 0) {
                    Color.parseColor("#00E5FF")
                } else {
                    Color.parseColor("#FFC857")
                }
                canvas.drawCircle(sx, sy, baseR * 0.085f, sparkPaint)
            }

            // Vector Heart Path
            heartPath.reset()
            heartPath.moveTo(cx, cy + r * 0.78f)
            heartPath.cubicTo(
                cx - r * 1.18f, cy + r * 0.14f,
                cx - r * 0.96f, cy - r * 0.88f,
                cx, cy - r * 0.25f
            )
            heartPath.cubicTo(
                cx + r * 0.96f, cy - r * 0.88f,
                cx + r * 1.18f, cy + r * 0.14f,
                cx, cy + r * 0.78f
            )
            heartPath.close()

            heartFillPaint.shader = LinearGradient(
                cx - r, cy - r,
                cx + r, cy + r,
                intArrayOf(
                    Color.parseColor("#FF3D9A"),
                    Color.parseColor("#B45CFF"),
                    Color.parseColor("#477BFF")
                ),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP
            )
            heartStrokePaint.strokeWidth = r * 0.09f
            canvas.drawPath(heartPath, heartFillPaint)
            canvas.drawPath(heartPath, heartStrokePaint)

            // Glossy inner core highlight
            sparkPaint.color = Color.argb(120, 255, 255, 255)
            canvas.drawCircle(cx - r * 0.32f, cy - r * 0.28f, r * 0.14f, sparkPaint)
        }
    }

    fun showFloatingHeartbeat(context: Context): Boolean {
        if (!canDraw(context)) return false
        mainHandler.post {
            try {
                val prefs = readPrefs(context)
                val (gravity, yOffset) = resolveGravityAndOffset(context, prefs.position)
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

                val container = LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    setPadding(dp(context, 18), dp(context, 14), dp(context, 18), dp(context, 16))
                    background = GradientDrawable(
                        GradientDrawable.Orientation.TOP_LEFT_BOTTOM_RIGHT,
                        intArrayOf(Color.parseColor("#E61A0D2E"), Color.parseColor("#EA080912"))
                    ).apply {
                        cornerRadius = dp(context, 32).toFloat()
                        setStroke(dp(context, 2), Color.parseColor("#FF3D9A"))
                    }
                    elevation = 28f
                }

                val heartView = GlowingVectorHeartView(
                    context,
                    intensity = prefs.intensity,
                    reducedMotion = prefs.reducedMotion
                ).apply {
                    val sz = dp(context, 138)
                    layoutParams = LinearLayout.LayoutParams(sz, sz)
                }

                val label = TextView(context).apply {
                    text = "تپش قلب زنده • Ghost Touch"
                    textSize = 12.5f
                    setTypeface(null, Typeface.BOLD)
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                }

                container.addView(heartView)
                container.addView(label)

                val params = overlayParams(touchable = false, gravity = gravity, yOffset = yOffset)
                wm.addView(container, params)

                if (!prefs.reducedMotion) {
                    val sx = ObjectAnimator.ofFloat(container, "scaleX", 0.65f, 1.06f, 1.0f)
                    val sy = ObjectAnimator.ofFloat(container, "scaleY", 0.65f, 1.06f, 1.0f)
                    AnimatorSet().apply {
                        playTogether(sx, sy)
                        duration = 420L
                        start()
                    }
                }

                mainHandler.postDelayed({
                    container.animate().alpha(0f).setDuration(360).withEndAction {
                        safeRemove(wm, container)
                    }.start()
                }, 2600L)
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
                    background = GradientDrawable(
                        GradientDrawable.Orientation.LEFT_RIGHT,
                        intArrayOf(Color.parseColor("#F0151124"), Color.parseColor("#F00B1426"))
                    ).apply {
                        cornerRadius = dp(context, 22).toFloat()
                        setStroke(dp(context, 2), Color.parseColor("#00FFA3"))
                    }
                    alpha = 0f
                    elevation = 24f
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
                pill.animate().alpha(1f).setDuration(240).start()

                mainHandler.postDelayed({
                    pill.animate().alpha(0f).setDuration(340).withEndAction {
                        safeRemove(wm, pill)
                    }.start()
                }, 3400L)
            } catch (_: Exception) {}
        }
        return true
    }

    private fun styleColors(style: String, fallbackHex: String): Triple<Int, Int, String> {
        val fallback = try {
            Color.parseColor(if (fallbackHex.isNotEmpty()) fallbackHex else "#FF3D9A")
        } catch (_: Exception) {
            Color.parseColor("#FF3D9A")
        }
        return when (style) {
            "floatingHeart" -> Triple(Color.parseColor("#FF3D9A"), Color.parseColor("#F02A0C24"), "💖 قلب هولوگرام")
            "cosmicPortal" -> Triple(Color.parseColor("#B45CFF"), Color.parseColor("#F0150D30"), "🌌 پورتال کیهانی")
            "particleAssembly" -> Triple(Color.parseColor("#477BFF"), Color.parseColor("#F00C1634"), "✨ ذرات نوری")
            "neonDrawingReveal" -> Triple(Color.parseColor("#FF3D9A"), Color.parseColor("#F0160E28"), "🎨 طراحی نئونی")
            "floatingSticker" -> Triple(Color.parseColor("#00FFA3"), Color.parseColor("#F00A1F20"), "🦋 استیکر هولوگرام")
            "digitalWave" -> Triple(Color.parseColor("#00E5FF"), Color.parseColor("#F0071B2B"), "〰️ موج دیجیتال")
            "surpriseBurst" -> Triple(Color.parseColor("#FFC857"), Color.parseColor("#F0261708"), "🎇 غافلگیری نوری")
            else -> Triple(fallback, Color.parseColor("#F2151124"), "⚡ کارت هولوگرافیک")
        }
    }

    fun showFloatingHologram(
        context: Context,
        emoji: String,
        title: String,
        body: String,
        pngBase64: String,
        colorHex: String,
        vanishSec: Int,
        hologramStyle: String = "holographicCard"
    ): Boolean {
        if (!canDraw(context)) return false
        mainHandler.post {
            try {
                val prefs = readPrefs(context)
                val (accent, surfaceBg, styleBadge) = styleColors(hologramStyle, colorHex)
                val (gravity, yOffset) = resolveGravityAndOffset(context, prefs.position)
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

                val card = LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER_HORIZONTAL
                    setPadding(dp(context, 20), dp(context, 16), dp(context, 20), dp(context, 18))
                    background = GradientDrawable(
                        GradientDrawable.Orientation.TOP_LEFT_BOTTOM_RIGHT,
                        intArrayOf(surfaceBg, Color.parseColor("#F4080912"))
                    ).apply {
                        cornerRadius = dp(context, 26).toFloat()
                        setStroke(dp(context, 2), accent)
                    }
                    elevation = 30f
                }

                var remaining = if (vanishSec > 0) vanishSec else prefs.durationSec
                var paused = false
                var dismissed = false

                val topRow = LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                val styleTv = TextView(context).apply {
                    text = styleBadge
                    textSize = 11.5f
                    setTypeface(null, Typeface.BOLD)
                    setTextColor(accent)
                    setPadding(0, 0, dp(context, 12), 0)
                }
                val timerBadge = TextView(context).apply {
                    text = "${remaining}s"
                    textSize = 12f
                    setTypeface(null, Typeface.BOLD)
                    setTextColor(Color.WHITE)
                    setPadding(dp(context, 8), dp(context, 3), dp(context, 8), dp(context, 3))
                    background = GradientDrawable().apply {
                        setColor(Color.parseColor("#26FFFFFF"))
                        cornerRadius = dp(context, 12).toFloat()
                    }
                }
                val closeBtn = TextView(context).apply {
                    text = " ✕ "
                    textSize = 15f
                    setTypeface(null, Typeface.BOLD)
                    setTextColor(Color.WHITE)
                    setPadding(dp(context, 8), dp(context, 3), dp(context, 8), dp(context, 3))
                    background = GradientDrawable().apply {
                        setColor(Color.parseColor("#33FFFFFF"))
                        cornerRadius = dp(context, 12).toFloat()
                    }
                }
                topRow.addView(styleTv)
                topRow.addView(timerBadge)
                val spacer = View(context).apply {
                    layoutParams = LinearLayout.LayoutParams(dp(context, 8), 1)
                }
                topRow.addView(spacer)
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

                if (emoji.isNotEmpty() && pngBase64.isEmpty()) {
                    val emojiTv = TextView(context).apply {
                        text = emoji
                        textSize = 54f
                        gravity = Gravity.CENTER
                        setPadding(0, dp(context, 10), 0, dp(context, 4))
                    }
                    card.addView(emojiTv)
                }

                if (title.isNotEmpty()) {
                    val titleTv = TextView(context).apply {
                        text = title
                        textSize = 16.5f
                        setTypeface(null, Typeface.BOLD)
                        setTextColor(accent)
                        gravity = Gravity.CENTER
                        maxWidth = dp(context, 280)
                        setPadding(0, dp(context, 6), 0, dp(context, 2))
                    }
                    card.addView(titleTv)
                }

                if (body.isNotEmpty()) {
                    val bodyTv = TextView(context).apply {
                        text = body
                        textSize = 15.5f
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
                timerBadge.setOnClickListener {
                    paused = !paused
                    timerBadge.text = if (paused) "⏸ ${remaining}s" else "${remaining}s"
                }

                val params = overlayParams(touchable = true, gravity = gravity, yOffset = yOffset)
                wm.addView(card, params)

                if (!prefs.reducedMotion) {
                    card.alpha = 0f
                    card.scaleX = 0.85f
                    card.scaleY = 0.85f
                    card.animate()
                        .alpha(1f)
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(300L)
                        .start()
                }

                val tickRunnable = object : Runnable {
                    override fun run() {
                        if (dismissed || !card.isAttachedToWindow) return
                        if (!paused) {
                            remaining--
                        }
                        if (remaining <= 0) {
                            dismissAction()
                        } else {
                            timerBadge.text = if (paused) "⏸ ${remaining}s" else "${remaining}s"
                            mainHandler.postDelayed(this, 1000L)
                        }
                    }
                }
                mainHandler.postDelayed(tickRunnable, 1000L)
            } catch (_: Exception) {}
        }
        return true
    }
}
