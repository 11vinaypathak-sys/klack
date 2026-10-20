package com.klack.keyboard

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import androidx.core.content.ContextCompat

/** A plain QWERTY keyboard drawn by hand. No Keyboard/KeyboardView (deprecated since API 29). */
class KeyboardView(context: Context) : View(context) {

    enum class Code { CHAR, SHIFT, BACKSPACE, SPACE, ENTER, SYMBOLS, LETTERS }
    enum class ShiftState { OFF, ON, CAPS }

    class Key(val code: Code, val label: String, val char: Char? = null, val weight: Float = 1f) {
        val bounds = RectF()
        var pressed = false
        val isSpecial get() = code != Code.CHAR && code != Code.SPACE
    }

    interface Listener {
        /** Finger landed on a key. Play the down sound here. */
        fun onKeyDown(key: Key)
        /** Finger lifted. Commit the key's action here and play the up sound. */
        fun onKeyUp(key: Key)
        /** Backspace held down: fires repeatedly. */
        fun onBackspaceRepeat()
    }

    var listener: Listener? = null
    var shiftState = ShiftState.OFF
        set(value) { field = value; invalidate() }
    private var symbols = false

    private val rows: List<List<Key>> get() = if (symbols) symbolRows else letterRows

    private val letterRows: List<List<Key>> = listOf(
        "1234567890".map { Key(Code.CHAR, it.toString(), it) },
        "qwertyuiop".map { Key(Code.CHAR, it.toString(), it) },
        "asdfghjkl".map { Key(Code.CHAR, it.toString(), it) },
        listOf(Key(Code.SHIFT, "⇧", weight = 1.5f)) +
            "zxcvbnm".map { Key(Code.CHAR, it.toString(), it) } +
            Key(Code.BACKSPACE, "⌫", weight = 1.5f),
        listOf(
            Key(Code.SYMBOLS, "?123", weight = 1.5f),
            Key(Code.CHAR, ",", ','),
            Key(Code.SPACE, "", ' ', weight = 5f),
            Key(Code.CHAR, ".", '.'),
            Key(Code.ENTER, "↵", weight = 1.5f),
        ),
    )

    private val symbolRows: List<List<Key>> = listOf(
        "1234567890".map { Key(Code.CHAR, it.toString(), it) },
        "@#\$_&-+()/".map { Key(Code.CHAR, it.toString(), it) },
        "*\"':;!?~".map { Key(Code.CHAR, it.toString(), it) },
        listOf(Key(Code.CHAR, "=", '=', weight = 1.5f)) +
            "<>[]{}%".map { Key(Code.CHAR, it.toString(), it) } +
            Key(Code.BACKSPACE, "⌫", weight = 1.5f),
        listOf(
            Key(Code.LETTERS, "ABC", weight = 1.5f),
            Key(Code.CHAR, ",", ','),
            Key(Code.SPACE, "", ' ', weight = 5f),
            Key(Code.CHAR, ".", '.'),
            Key(Code.ENTER, "↵", weight = 1.5f),
        ),
    )

    private val bgColor = ContextCompat.getColor(context, R.color.kb_background)
    private val keyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ContextCompat.getColor(context, R.color.kb_key) }
    private val specialPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ContextCompat.getColor(context, R.color.kb_key_special) }
    private val pressedPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ContextCompat.getColor(context, R.color.kb_key_pressed) }
    private val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ContextCompat.getColor(context, R.color.kb_accent) }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.kb_key_text)
        textAlign = Paint.Align.CENTER
        typeface = Typeface.DEFAULT
        textSize = sp(20f)
    }

    private val gap = dp(4f)
    private val rowHeight = dp(52f)
    private val corner = dp(8f)

    /** pointerId -> key currently under that finger. */
    private val active = HashMap<Int, Key>()
    private val handler = Handler(Looper.getMainLooper())
    private var lastShiftTap = 0L

    private val backspaceRepeat = object : Runnable {
        override fun run() {
            listener?.onBackspaceRepeat()
            handler.postDelayed(this, REPEAT_INTERVAL_MS)
        }
    }

    private fun dp(v: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics)
    private fun sp(v: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, v, resources.displayMetrics)

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val h = (rows.size * rowHeight + gap * 2 + paddingBottom).toInt()
        setMeasuredDimension(w, h)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) = layoutKeys()

    private fun layoutKeys() {
        val w = width.toFloat()
        if (w <= 0) return
        var y = gap
        for (row in rows) {
            val totalWeight = row.sumOf { it.weight.toDouble() }.toFloat()
            val unit = (w - gap) / totalWeight
            var x = gap
            for (key in row) {
                val kw = unit * key.weight - gap
                key.bounds.set(x, y, x + kw, y + rowHeight - gap)
                x += kw + gap
            }
            y += rowHeight
        }
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(bgColor)
        for (row in rows) for (key in row) {
            val paint = when {
                key.pressed -> pressedPaint
                key.code == Code.SHIFT && shiftState != ShiftState.OFF -> accentPaint
                key.isSpecial -> specialPaint
                else -> keyPaint
            }
            canvas.drawRoundRect(key.bounds, corner, corner, paint)
            val label = labelFor(key)
            if (label.isNotEmpty()) {
                val baseline = key.bounds.centerY() - (textPaint.descent() + textPaint.ascent()) / 2
                canvas.drawText(label, key.bounds.centerX(), baseline, textPaint)
            }
        }
    }

    private fun labelFor(key: Key): String = when {
        key.code == Code.SHIFT && shiftState == ShiftState.CAPS -> "⇪"
        key.code == Code.CHAR && key.char?.isLetter() == true && shiftState != ShiftState.OFF -> key.label.uppercase()
        else -> key.label
    }

    /** The character this key produces right now, honouring shift. */
    fun textFor(key: Key): String? {
        val c = key.char ?: return null
        return if (shiftState != ShiftState.OFF && c.isLetter()) c.uppercase() else c.toString()
    }

    private fun keyAt(x: Float, y: Float): Key? {
        for (row in rows) for (key in row) if (key.bounds.contains(x, y)) return key
        // Fingers land between keys constantly; snap to the nearest key in the row that was hit.
        for (row in rows) {
            val first = row.firstOrNull() ?: continue
            if (y >= first.bounds.top - gap && y <= first.bounds.bottom + gap) {
                return row.minByOrNull { kotlin.math.abs(it.bounds.centerX() - x) }
            }
        }
        return null
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = event.actionIndex
                val key = keyAt(event.getX(i), event.getY(i)) ?: return true
                press(event.getPointerId(i), key)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                release(event.getPointerId(event.actionIndex), cancelled = false)
            }
            MotionEvent.ACTION_CANCEL -> {
                for (id in active.keys.toList()) release(id, cancelled = true)
            }
        }
        return true
    }

    private fun press(pointerId: Int, key: Key) {
        active[pointerId] = key
        key.pressed = true
        performHapticFeedbackSafely()
        listener?.onKeyDown(key)
        if (key.code == Code.BACKSPACE) {
            handler.postDelayed(backspaceRepeat, REPEAT_DELAY_MS)
        }
        invalidate()
    }

    private fun release(pointerId: Int, cancelled: Boolean) {
        val key = active.remove(pointerId) ?: return
        key.pressed = false
        if (key.code == Code.BACKSPACE) handler.removeCallbacks(backspaceRepeat)
        if (!cancelled) {
            when (key.code) {
                Code.SHIFT -> {
                    val now = SystemClock.uptimeMillis()
                    shiftState = when {
                        now - lastShiftTap < DOUBLE_TAP_MS -> ShiftState.CAPS
                        shiftState == ShiftState.OFF -> ShiftState.ON
                        else -> ShiftState.OFF
                    }
                    lastShiftTap = now
                }
                Code.SYMBOLS -> { symbols = true; layoutKeys() }
                Code.LETTERS -> { symbols = false; layoutKeys() }
                else -> {}
            }
            listener?.onKeyUp(key)
            // One-shot shift drops after a letter; caps lock stays.
            if (key.code == Code.CHAR && shiftState == ShiftState.ON) shiftState = ShiftState.OFF
        }
        invalidate()
    }

    private fun performHapticFeedbackSafely() {
        try { performHapticFeedback(android.view.HapticFeedbackConstants.KEYBOARD_TAP) } catch (_: Throwable) {}
    }

    override fun onDetachedFromWindow() {
        handler.removeCallbacks(backspaceRepeat)
        super.onDetachedFromWindow()
    }

    companion object {
        private const val REPEAT_DELAY_MS = 400L
        private const val REPEAT_INTERVAL_MS = 50L
        private const val DOUBLE_TAP_MS = 350L
    }
}
