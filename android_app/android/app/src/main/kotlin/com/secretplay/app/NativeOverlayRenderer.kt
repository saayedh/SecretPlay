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
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
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
            reducedMotion = sp.getBoolean(StealthStandbyService.KEY_GT_REDUCED_MOTION, false),
            soundEnabled = sp.getBoolean(StealthStandbyService.KEY_GT_SOUND, true)
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
        val reducedMotion: Boolean,
        val soundEnabled: Boolean
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
                val (overlayGravity, yOffset) = resolveGravityAndOffset(context, prefs.position)
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

                val container = LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    setGravity(Gravity.CENTER)
                    setPadding(dp(context, 18), dp(context, 14), dp(context, 18), dp(context, 16))
                    background = GradientDrawable(
                        GradientDrawable.Orientation.TL_BR,
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

                val params = overlayParams(touchable = false, gravity = overlayGravity, yOffset = yOffset)
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

    /**
     * Hardware-accelerated backdrop view inside floating native hologram overlays.
     * Renders distinct animated effects for all 8 HologramStyles, plus interactive
     * single-tap particle bursts and double-tap shockwaves.
     */
    private class HologramEffectBackdropView(
        context: Context,
        private val style: String,
        private val accentColor: Int,
        private val intensity: Float,
        private val reducedMotion: Boolean
    ) : View(context) {
        private var ambientProgress = 0.25f
        private var burstProgress = 0f
        private var burstX = 0.5f
        private var burstY = 0.5f
        private var shockwaveProgress = 0f

        private var ambientAnim: ValueAnimator? = null
        private var burstAnim: ValueAnimator? = null
        private var shockAnim: ValueAnimator? = null

        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val tempPath = Path()

        private fun withAlpha(color: Int, alphaFloat: Float): Int {
            val a = (alphaFloat.coerceIn(0f, 1f) * 255f).toInt()
            return Color.argb(a, Color.red(color), Color.green(color), Color.blue(color))
        }

        fun triggerBurst(xPx: Float, yPx: Float) {
            if (width > 0 && height > 0) {
                burstX = (xPx / width.toFloat()).coerceIn(0.08f, 0.92f)
                burstY = (yPx / height.toFloat()).coerceIn(0.08f, 0.92f)
            }
            burstAnim?.cancel()
            burstAnim = ValueAnimator.ofFloat(0.01f, 1f).apply {
                duration = 620L
                interpolator = LinearInterpolator()
                addUpdateListener {
                    burstProgress = it.animatedValue as Float
                    if (burstProgress >= 0.99f) burstProgress = 0f
                    invalidate()
                }
                start()
            }
        }

        fun triggerShockwave() {
            shockAnim?.cancel()
            shockAnim = ValueAnimator.ofFloat(0.01f, 1f).apply {
                duration = 880L
                interpolator = LinearInterpolator()
                addUpdateListener {
                    shockwaveProgress = it.animatedValue as Float
                    if (shockwaveProgress >= 0.99f) shockwaveProgress = 0f
                    invalidate()
                }
                start()
            }
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            if (!reducedMotion && ambientAnim == null) {
                ambientAnim = ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = 3200L
                    repeatCount = ValueAnimator.INFINITE
                    interpolator = LinearInterpolator()
                    addUpdateListener {
                        ambientProgress = it.animatedValue as Float
                        invalidate()
                    }
                    start()
                }
            }
        }

        override fun onDetachedFromWindow() {
            ambientAnim?.cancel()
            ambientAnim = null
            burstAnim?.cancel()
            burstAnim = null
            shockAnim?.cancel()
            shockAnim = null
            super.onDetachedFromWindow()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (width <= 0 || height <= 0) return

            val w = width.toFloat()
            val h = height.toFloat()
            val cx = w / 2f
            val cy = h / 2f
            val minDim = min(w, h)
            val k = intensity.coerceIn(0.2f, 1.0f)
            val phase = ambientProgress * (Math.PI * 2.0)

            // Ambient radial glow under card
            val glowR = (minDim * 0.72f).coerceAtLeast(1f)
            fillPaint.shader = RadialGradient(
                cx,
                cy,
                glowR,
                intArrayOf(
                    withAlpha(accentColor, 0.22f * k),
                    withAlpha(accentColor, 0.06f * k),
                    Color.TRANSPARENT
                ),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(cx, cy, glowR, fillPaint)
            fillPaint.shader = null

            when (style) {
                "floatingHeart" -> {
                    for (i in 0 until 3) {
                        val r = minDim * (0.22f + i * 0.11f + 0.025f * sin(phase + i).toFloat())
                        tempPath.reset()
                        tempPath.moveTo(cx, cy + r * 0.72f)
                        tempPath.cubicTo(
                            cx - r * 1.15f, cy + r * 0.1f,
                            cx - r * 0.9f, cy - r * 0.85f,
                            cx, cy - r * 0.25f
                        )
                        tempPath.cubicTo(
                            cx + r * 0.9f, cy - r * 0.85f,
                            cx + r * 1.15f, cy + r * 0.1f,
                            cx, cy + r * 0.72f
                        )
                        strokePaint.color = withAlpha(accentColor, (0.30f - i * 0.08f) * k)
                        strokePaint.strokeWidth = 3f
                        canvas.drawPath(tempPath, strokePaint)
                    }
                }

                "cosmicPortal" -> {
                    for (i in 0 until 4) {
                        canvas.save()
                        canvas.translate(cx, cy)
                        val deg = Math.toDegrees(phase * (if (i % 2 == 0) 1.0 else -1.0) + i * 0.6).toFloat()
                        canvas.rotate(deg)
                        val rw = minDim * (0.34f + i * 0.08f)
                        val rh = minDim * (0.20f + i * 0.05f)
                        val col = if (i % 2 == 0) accentColor else Color.parseColor("#00E5FF")
                        strokePaint.color = withAlpha(col, 0.28f * k)
                        strokePaint.strokeWidth = 2.6f
                        canvas.drawOval(-rw, -rh, rw, rh, strokePaint)
                        canvas.restore()
                    }
                }

                "particleAssembly", "surpriseBurst" -> {
                    for (i in 0 until 18) {
                        val ang = (i / 18.0) * Math.PI * 2.0 + phase * 0.45
                        val t = ((ambientProgress + i * 0.07f) % 1f)
                        val dist = minDim * if (style == "particleAssembly") {
                            0.48f - 0.20f * t
                        } else {
                            0.20f + 0.28f * t
                        }
                        val px = cx + (cos(ang) * dist).toFloat()
                        val py = cy + (sin(ang) * dist).toFloat()
                        val col = if (i % 3 == 0) Color.parseColor("#FFC857") else accentColor
                        fillPaint.color = withAlpha(col, 0.50f * k)
                        canvas.drawCircle(px, py, 3.2f + (i % 3) * 1.4f, fillPaint)
                    }
                }

                "neonDrawingReveal" -> {
                    val scanY = ambientProgress * h
                    strokePaint.color = withAlpha(Color.parseColor("#00E5FF"), 0.42f * k)
                    strokePaint.strokeWidth = 3.5f
                    canvas.drawLine(0f, scanY, w, scanY, strokePaint)
                    fillPaint.color = withAlpha(Color.parseColor("#00E5FF"), 0.12f * k)
                    canvas.drawRect(0f, (scanY - 22f).coerceAtLeast(0f), w, scanY, fillPaint)
                }

                "digitalWave" -> {
                    for (wIdx in 0 until 2) {
                        tempPath.reset()
                        tempPath.moveTo(0f, cy)
                        var x = 0f
                        while (x <= w) {
                            val y = cy + sin(x * 0.025 + phase * (wIdx + 1)).toFloat() * (28f + wIdx * 14f)
                            tempPath.lineTo(x, y)
                            x += 12f
                        }
                        val col = if (wIdx == 0) accentColor else Color.parseColor("#00FFA3")
                        strokePaint.color = withAlpha(col, 0.34f * k)
                        strokePaint.strokeWidth = 3f
                        canvas.drawPath(tempPath, strokePaint)
                    }
                }

                "floatingSticker" -> {
                    val orbitR = minDim * 0.40f
                    strokePaint.color = withAlpha(accentColor, 0.25f * k)
                    strokePaint.strokeWidth = 2.4f
                    canvas.drawCircle(cx, cy, orbitR, strokePaint)
                    for (i in 0 until 8) {
                        val a = phase + i * (Math.PI / 4.0)
                        val px = cx + (cos(a) * orbitR).toFloat()
                        val py = cy + (sin(a) * orbitR).toFloat()
                        val col = if (i % 2 == 0) Color.WHITE else accentColor
                        fillPaint.color = withAlpha(col, 0.65f * k)
                        canvas.drawCircle(px, py, 3.4f, fillPaint)
                    }
                }

                else -> {
                    val sheenX = -w * 0.2f + ambientProgress * w * 1.4f
                    strokePaint.color = Color.argb((24 * k).toInt(), 255, 255, 255)
                    strokePaint.strokeWidth = 36f
                    canvas.drawLine(sheenX, 0f, sheenX - 50f, h, strokePaint)
                    val pulseR = minDim * (0.34f + 0.04f * sin(phase).toFloat())
                    strokePaint.color = withAlpha(accentColor, 0.24f * k)
                    strokePaint.strokeWidth = 2.2f
                    canvas.drawCircle(cx, cy, pulseR, strokePaint)
                }
            }

            // Tap Particle Burst
            if (burstProgress > 0f && burstProgress < 1f) {
                val ox = burstX * w
                val oy = burstY * h
                val fade = (1f - burstProgress).coerceIn(0f, 1f)
                for (i in 0 until 14) {
                    val a = (i / 14.0) * Math.PI * 2.0
                    val dist = 16f + burstProgress * minDim * 0.42f
                    val px = ox + (cos(a) * dist).toFloat()
                    val py = oy + (sin(a) * dist).toFloat()
                    val col = if (i % 2 == 0) Color.WHITE else accentColor
                    fillPaint.color = withAlpha(col, fade * 0.9f)
                    canvas.drawCircle(px, py, 4.5f * fade + 1.5f, fillPaint)
                }
                strokePaint.color = withAlpha(accentColor, fade * 0.65f)
                strokePaint.strokeWidth = 3f
                canvas.drawCircle(ox, oy, 12f + burstProgress * minDim * 0.32f, strokePaint)
            }

            // Double-Tap Mega Heartbeat Shockwave
            if (shockwaveProgress > 0f && shockwaveProgress < 1f) {
                val fade = (1f - shockwaveProgress).coerceIn(0f, 1f)
                strokePaint.color = withAlpha(Color.parseColor("#FF3D9A"), fade * 0.85f)
                strokePaint.strokeWidth = 5.5f * fade + 1.5f
                canvas.drawCircle(cx, cy, minDim * (0.14f + shockwaveProgress * 0.62f), strokePaint)
                strokePaint.color = withAlpha(Color.parseColor("#00E5FF"), fade * 0.60f)
                strokePaint.strokeWidth = 3f * fade + 1f
                canvas.drawCircle(cx, cy, minDim * (0.08f + shockwaveProgress * 0.46f), strokePaint)
            }
        }
    }

    /**
     * Custom Canvas View rendering distinct vector bursts for Spark, Bolt, and Hug reactions.
     */
    private class GlowingReactionBurstView(
        context: Context,
        private val reactionType: String,
        private val intensity: Float,
        private val reducedMotion: Boolean
    ) : View(context) {
        private var progress = 0.25f
        private var animator: ValueAnimator? = null
        private val auraPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val motifPath = Path()

        private val primaryColor: Int = when (reactionType) {
            "spark" -> Color.parseColor("#FFC857")
            "bolt" -> Color.parseColor("#00E5FF")
            "hug" -> Color.parseColor("#00FFA3")
            else -> Color.parseColor("#FF3D9A")
        }

        private val secondaryColor: Int = when (reactionType) {
            "spark" -> Color.parseColor("#FF3D9A")
            "bolt" -> Color.parseColor("#B45CFF")
            "hug" -> Color.parseColor("#FF3D9A")
            else -> Color.parseColor("#00E5FF")
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            if (!reducedMotion && animator == null) {
                animator = ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = 1500L
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
            if (width <= 0 || height <= 0) return

            val cx = width / 2f
            val cy = height / 2f
            val baseR = min(width, height) * 0.27f
            val phase = progress * Math.PI * 2.0
            val pulse = if (reducedMotion) 0f else (sin(phase).toFloat() * 0.12f)
            val r = baseR * (1f + pulse)

            val auraR = (baseR * 1.85f).coerceAtLeast(1f)
            auraPaint.shader = RadialGradient(
                cx,
                cy,
                auraR,
                intArrayOf(
                    Color.argb((125 * intensity).toInt(), Color.red(primaryColor), Color.green(primaryColor), Color.blue(primaryColor)),
                    Color.argb((45 * intensity).toInt(), Color.red(secondaryColor), Color.green(secondaryColor), Color.blue(secondaryColor)),
                    Color.TRANSPARENT
                ),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawCircle(cx, cy, auraR, auraPaint)

            if (!reducedMotion) {
                val ringAlpha = ((1f - progress) * 180f * intensity).toInt().coerceIn(0, 255)
                strokePaint.color = Color.argb(ringAlpha, Color.red(secondaryColor), Color.green(secondaryColor), Color.blue(secondaryColor))
                strokePaint.strokeWidth = baseR * 0.08f
                canvas.drawCircle(cx, cy, baseR * (0.95f + progress * 0.85f), strokePaint)
            }

            for (i in 0 until 6) {
                val a = phase + i * (Math.PI / 3.0)
                val sx = cx + (cos(a) * baseR * 1.35f).toFloat()
                val sy = cy + (sin(a) * baseR * 1.35f).toFloat()
                fillPaint.color = if (i % 2 == 0) primaryColor else Color.WHITE
                canvas.drawCircle(sx, sy, baseR * 0.08f, fillPaint)
            }

            motifPath.reset()
            when (reactionType) {
                "spark" -> {
                    motifPath.moveTo(cx, cy - r * 1.05f)
                    motifPath.quadTo(cx, cy, cx + r * 1.05f, cy)
                    motifPath.quadTo(cx, cy, cx, cy + r * 1.05f)
                    motifPath.quadTo(cx, cy, cx - r * 1.05f, cy)
                    motifPath.quadTo(cx, cy, cx, cy - r * 1.05f)
                    motifPath.close()
                }
                "bolt" -> {
                    motifPath.moveTo(cx + r * 0.16f, cy - r * 1.05f)
                    motifPath.lineTo(cx - r * 0.62f, cy + r * 0.08f)
                    motifPath.lineTo(cx + r * 0.06f, cy + r * 0.08f)
                    motifPath.lineTo(cx - r * 0.24f, cy + r * 1.05f)
                    motifPath.lineTo(cx + r * 0.66f, cy - r * 0.12f)
                    motifPath.lineTo(cx - r * 0.04f, cy - r * 0.12f)
                    motifPath.close()
                }
                else -> {
                    strokePaint.color = primaryColor
                    strokePaint.strokeWidth = r * 0.22f
                    canvas.drawArc(cx - r, cy - r * 0.82f, cx + r * 0.4f, cy + r * 0.82f, 110f, 150f, false, strokePaint)
                    strokePaint.color = secondaryColor
                    canvas.drawArc(cx - r * 0.4f, cy - r * 0.82f, cx + r, cy + r * 0.82f, -80f, 150f, false, strokePaint)
                    fillPaint.color = Color.WHITE
                    canvas.drawCircle(cx, cy, r * 0.26f, fillPaint)
                    return
                }
            }

            fillPaint.shader = LinearGradient(
                cx - r, cy - r, cx + r, cy + r,
                intArrayOf(primaryColor, secondaryColor),
                floatArrayOf(0f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawPath(motifPath, fillPaint)
            fillPaint.shader = null
            strokePaint.color = Color.WHITE
            strokePaint.strokeWidth = r * 0.08f
            canvas.drawPath(motifPath, strokePaint)
        }
    }

    fun showFloatingReactionBurst(context: Context, reactionType: String): Boolean {
        if (reactionType == "heart" || reactionType == "mega_heart") {
            return showFloatingHeartbeat(context)
        }
        if (!canDraw(context)) return false
        mainHandler.post {
            try {
                val prefs = readPrefs(context)
                val (overlayGravity, yOffset) = resolveGravityAndOffset(context, prefs.position)
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

                val (borderHex, captionText) = when (reactionType) {
                    "spark" -> "#FFC857" to "✨ جرقه طلایی • Ghost Touch"
                    "bolt" -> "#00E5FF" to "⚡ موج انرژی سایبری • Ghost Touch"
                    "hug" -> "#00FFA3" to "🫂 بغل مجازی گرم • Ghost Touch"
                    else -> "#FF3D9A" to "💖 واکنش هولوگرام • Ghost Touch"
                }

                val container = LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    setGravity(Gravity.CENTER)
                    setPadding(dp(context, 18), dp(context, 14), dp(context, 18), dp(context, 16))
                    background = GradientDrawable(
                        GradientDrawable.Orientation.TL_BR,
                        intArrayOf(Color.parseColor("#E616102A"), Color.parseColor("#EA080912"))
                    ).apply {
                        cornerRadius = dp(context, 32).toFloat()
                        setStroke(dp(context, 2), Color.parseColor(borderHex))
                    }
                    elevation = 28f
                }

                val burstView = GlowingReactionBurstView(
                    context,
                    reactionType = reactionType,
                    intensity = prefs.intensity,
                    reducedMotion = prefs.reducedMotion
                ).apply {
                    val sz = dp(context, 134)
                    layoutParams = LinearLayout.LayoutParams(sz, sz)
                }

                val label = TextView(context).apply {
                    text = captionText
                    textSize = 12.5f
                    setTypeface(null, Typeface.BOLD)
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                }

                container.addView(burstView)
                container.addView(label)

                val params = overlayParams(touchable = false, gravity = overlayGravity, yOffset = yOffset)
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
        hologramStyle: String = "holographicCard",
        senderDeviceId: String = "",
        cardDataJson: String = "",
        onSendReaction: ((String) -> Unit)? = null
    ): Boolean {
        if (!canDraw(context)) return false
        mainHandler.post {
            try {
                val prefs = readPrefs(context)
                var resolvedAccentHex = colorHex
                var resolvedTextColor = Color.WHITE
                var resolvedBody = body

                if (cardDataJson.isNotEmpty()) {
                    try {
                        val cardObj = JSONObject(cardDataJson)
                        val cardAccent = cardObj.optString("accentColorHex", "")
                        if (cardAccent.isNotEmpty()) resolvedAccentHex = cardAccent
                        val cardTextHex = cardObj.optString("textColorHex", "")
                        if (cardTextHex.isNotEmpty()) {
                            resolvedTextColor = Color.parseColor(cardTextHex)
                        }
                        val cardText = cardObj.optString("text", "")
                        if (cardText.isNotEmpty()) resolvedBody = cardText
                    } catch (_: Exception) {}
                }

                val (baseAccent, surfaceBg, styleBadge) = styleColors(hologramStyle, resolvedAccentHex)
                val accent = try {
                    if (cardDataJson.isNotEmpty() && resolvedAccentHex.isNotEmpty()) {
                        Color.parseColor(resolvedAccentHex)
                    } else {
                        baseAccent
                    }
                } catch (_: Exception) {
                    baseAccent
                }

                val (overlayGravity, yOffset) = resolveGravityAndOffset(context, prefs.position)
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

                val rootFrame = FrameLayout(context).apply {
                    background = GradientDrawable(
                        GradientDrawable.Orientation.TL_BR,
                        intArrayOf(surfaceBg, Color.parseColor("#F4080912"))
                    ).apply {
                        cornerRadius = dp(context, 26).toFloat()
                        setStroke(dp(context, 2), accent)
                    }
                    elevation = 30f
                    clipToOutline = true
                }

                val backdropView = HologramEffectBackdropView(
                    context = context,
                    style = hologramStyle,
                    accentColor = accent,
                    intensity = prefs.intensity,
                    reducedMotion = prefs.reducedMotion
                ).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                }
                rootFrame.addView(backdropView)

                val card = LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    setGravity(Gravity.CENTER_HORIZONTAL)
                    setPadding(dp(context, 20), dp(context, 16), dp(context, 20), dp(context, 16))
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT
                    )
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

                var hasDecodedBitmap = false
                if (pngBase64.isNotEmpty()) {
                    try {
                        val bytes = Base64.decode(pngBase64, Base64.DEFAULT)
                        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        if (bmp != null) {
                            hasDecodedBitmap = true
                            val imgView = ImageView(context).apply {
                                setImageBitmap(bmp)
                                adjustViewBounds = true
                                maxWidth = dp(context, 280)
                                maxHeight = dp(context, 230)
                                scaleType = ImageView.ScaleType.FIT_CENTER
                                setPadding(0, dp(context, 12), 0, dp(context, 6))
                            }
                            card.addView(imgView)
                        }
                    } catch (_: Exception) {}
                }

                if (emoji.isNotEmpty() && !hasDecodedBitmap) {
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
                        textSize = 15.5f
                        setTypeface(null, Typeface.BOLD)
                        setTextColor(accent)
                        gravity = Gravity.CENTER
                        maxWidth = dp(context, 280)
                        setPadding(0, dp(context, 6), 0, dp(context, 2))
                    }
                    card.addView(titleTv)
                }

                if (resolvedBody.isNotEmpty()) {
                    val bodyTv = TextView(context).apply {
                        text = resolvedBody
                        textSize = 15.5f
                        setTypeface(null, Typeface.BOLD)
                        setTextColor(resolvedTextColor)
                        gravity = Gravity.CENTER
                        maxWidth = dp(context, 280)
                        setPadding(0, dp(context, 6), 0, dp(context, 4))
                    }
                    card.addView(bodyTv)
                }

                val hintTv = TextView(context).apply {
                    text = "ضربه = انفجار نور • دابل‌تپ = شوک قلب"
                    textSize = 10f
                    setTextColor(Color.parseColor("#88FFFFFF"))
                    gravity = Gravity.CENTER
                    setPadding(0, dp(context, 4), 0, dp(context, 6))
                }
                card.addView(hintTv)

                if (onSendReaction != null && senderDeviceId.isNotEmpty()) {
                    val reactRow = LinearLayout(context).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER
                        setPadding(0, dp(context, 2), 0, dp(context, 2))
                    }
                    val pills = listOf(
                        Triple("heart", "❤️", "#FF3D9A"),
                        Triple("spark", "✨", "#FFC857"),
                        Triple("bolt", "⚡", "#00E5FF"),
                        Triple("hug", "🫂", "#00FFA3")
                    )
                    for ((idx, item) in pills.withIndex()) {
                        val (key, glyph, hexCol) = item
                        val pillCol = Color.parseColor(hexCol)
                        val btn = TextView(context).apply {
                            text = glyph
                            textSize = 16f
                            gravity = Gravity.CENTER
                            setPadding(dp(context, 12), dp(context, 5), dp(context, 12), dp(context, 5))
                            background = GradientDrawable().apply {
                                setColor(Color.argb(46, Color.red(pillCol), Color.green(pillCol), Color.blue(pillCol)))
                                cornerRadius = dp(context, 14).toFloat()
                                setStroke(dp(context, 1), pillCol)
                            }
                            setOnClickListener {
                                backdropView.triggerBurst(rootFrame.width / 2f, rootFrame.height * 0.72f)
                                onSendReaction(key)
                            }
                        }
                        if (idx > 0) {
                            reactRow.addView(View(context).apply {
                                layoutParams = LinearLayout.LayoutParams(dp(context, 8), 1)
                            })
                        }
                        reactRow.addView(btn)
                    }
                    card.addView(reactRow)
                }

                rootFrame.addView(card)

                val dismissAction = {
                    if (!dismissed) {
                        dismissed = true
                        safeRemove(wm, rootFrame)
                    }
                }
                closeBtn.setOnClickListener { dismissAction() }
                timerBadge.setOnClickListener {
                    paused = !paused
                    timerBadge.text = if (paused) "⏸ ${remaining}s" else "${remaining}s"
                }

                val gestureDetector = GestureDetector(
                    context,
                    object : GestureDetector.SimpleOnGestureListener() {
                        override fun onDown(e: MotionEvent): Boolean = true

                        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                            backdropView.triggerBurst(e.x, e.y)
                            return true
                        }

                        override fun onDoubleTap(e: MotionEvent): Boolean {
                            backdropView.triggerShockwave()
                            backdropView.triggerBurst(e.x, e.y)
                            paused = true
                            timerBadge.text = "⏸ ${remaining}s"
                            if (senderDeviceId.isNotEmpty()) {
                                onSendReaction?.invoke("mega_heart")
                            }
                            return true
                        }
                    }
                )
                card.setOnTouchListener { v, event ->
                    val handled = gestureDetector.onTouchEvent(event)
                    if (handled && event.action == MotionEvent.ACTION_UP) {
                        v.performClick()
                    }
                    true
                }

                val params = overlayParams(touchable = true, gravity = overlayGravity, yOffset = yOffset)
                wm.addView(rootFrame, params)

                if (!prefs.reducedMotion) {
                    rootFrame.alpha = 0f
                    rootFrame.scaleX = 0.85f
                    rootFrame.scaleY = 0.85f
                    rootFrame.animate()
                        .alpha(1f)
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(300L)
                        .start()
                }

                val tickRunnable = object : Runnable {
                    override fun run() {
                        if (dismissed || !rootFrame.isAttachedToWindow) return
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
