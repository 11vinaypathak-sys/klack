package com.klack.keyboard

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import kotlin.math.PI
import kotlin.math.cos
import kotlin.random.Random

/**
 * Plays the Klack click samples for one key press/release.
 *
 * A port of the behaviour in Sources/Klack/AudioEngine.swift (the macOS app):
 *  - random down variant on press, random up variant on release, a dedicated pair for space;
 *  - once typing turns into a burst the down variants are walked up-and-down instead of
 *    picked at random, so a run reads as a phrase rather than gravel;
 *  - per-hit gain drops as typing speed rises (never rises);
 *  - each new key-down fades whatever is still ringing (raised-cosine release that
 *    shortens with typing speed) so the newest click dominates.
 *
 * SoundPool is used because it is the lowest-latency path Android offers for short,
 * fully-decoded samples and it mixes overlapping streams for us. Volume follows the
 * device media stream (USAGE_MEDIA) multiplied by the user's in-app volume.
 */
class ClickSoundEngine(private val context: Context) {

    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(MAX_STREAMS)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()

    private val handler = Handler(Looper.getMainLooper())
    private val rng = Random(System.nanoTime())

    private var downIds = IntArray(0)
    private var upIds = IntArray(0)
    private var spaceDownId = 0
    private var spaceUpId = 0
    private val loaded = HashSet<Int>()

    /** 0..1 user volume, applied on top of the media stream. */
    @Volatile var volume: Float = KlackSettings.DEFAULT_VOLUME
        set(value) { field = value.coerceIn(0f, 1f) }

    var currentPack: String = ""
        private set

    // --- typing flow (AppDelegate.recordKeyDownAndComputeFlow) -----------------------
    private val recentDownTimes = ArrayDeque<Long>()

    // --- melodic walk (AudioEngine.nextDownVariant) -----------------------------------
    private var melodyIndex = 0
    private var melodyStep = 1

    // --- ducking (AudioEngine.DuckingVoice) -------------------------------------------
    private class DuckingVoice(val streamId: Int, val startVolume: Float, val releaseSec: Double) {
        var elapsed = 0.0
    }
    private val ducking = ArrayList<DuckingVoice>()
    private var lastDuckTick = 0L
    private val duckTick = object : Runnable {
        override fun run() { tickDucking() }
    }

    init {
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0) loaded.add(sampleId)
            else Log.w(TAG, "sample $sampleId failed to load (status $status)")
        }
    }

    /** Loads a pack from assets/profiles/<name>/. Safe to call again to switch packs. */
    fun loadPack(name: String) {
        if (name == currentPack && downIds.isNotEmpty()) return
        unloadAll()
        val am = context.assets
        val dir = "profiles/$name"
        val files = am.list(dir)?.toSet().orEmpty()
        if (files.isEmpty()) {
            Log.e(TAG, "pack '$name' has no files in assets/$dir")
            return
        }
        fun load(file: String): Int =
            if (file in files) am.openFd("$dir/$file").use { pool.load(it, 1) } else 0

        downIds = (1..MAX_VARIANTS).map { load("click_down_$it.wav") }.filter { it != 0 }.toIntArray()
        upIds = (1..MAX_VARIANTS).map { load("click_up_$it.wav") }.filter { it != 0 }.toIntArray()
        spaceDownId = load("click_space_down.wav")
        spaceUpId = load("click_space_up.wav")
        currentPack = name
        melodyIndex = 0
        melodyStep = 1
        Log.i(TAG, "loaded pack '$name': ${downIds.size} down, ${upIds.size} up, space=${spaceDownId != 0}")
    }

    private fun unloadAll() {
        cancelDucking()
        (downIds.asList() + upIds.asList() + listOf(spaceDownId, spaceUpId))
            .filter { it != 0 }.forEach { pool.unload(it) }
        loaded.clear()
        downIds = IntArray(0); upIds = IntArray(0); spaceDownId = 0; spaceUpId = 0
    }

    fun release() {
        cancelDucking()
        pool.release()
    }

    // ----------------------------------------------------------------------------------

    fun keyDown(isSpace: Boolean) {
        val flow = recordKeyDownAndComputeFlow()
        val gain = burstGain(flow)
        val fade = releaseFor(flow)
        val id = if (isSpace) {
            spaceDownId.takeIf { it != 0 } ?: pickDown(melodic = false)
        } else {
            pickDown(melodic = flow > 0.35f)
        }
        if (id != 0) play(id, gain, ducksOthers = true, releaseSec = fade)
    }

    fun keyUp(isSpace: Boolean) {
        val id = if (isSpace && spaceUpId != 0) spaceUpId
        else if (upIds.isNotEmpty()) upIds[rng.nextInt(upIds.size)]
        else 0
        if (id != 0) play(id, gain = 1f, ducksOthers = false, releaseSec = 0.0)
    }

    /** Plays a short demo burst from the settings screen. */
    fun preview() {
        var delay = 0L
        val pattern = listOf(false, false, false, true, false, false)
        for (space in pattern) {
            handler.postDelayed({ keyDown(space) }, delay)
            handler.postDelayed({ keyUp(space) }, delay + 70)
            delay += 140
        }
    }

    // ----------------------------------------------------------------------------------

    /**
     * Walks the variants up and down instead of picking at random once typing is a burst.
     * Random selection is what makes a fast run sound like gravel; a rising-then-falling
     * contour is enough for the ear to hear a phrase. Slow typing stays random.
     */
    private fun pickDown(melodic: Boolean): Int {
        if (downIds.isEmpty()) return 0
        if (!melodic || downIds.size < 2) return downIds[rng.nextInt(downIds.size)]
        melodyIndex += melodyStep
        if (melodyIndex >= downIds.size - 1) {
            melodyIndex = downIds.size - 1; melodyStep = -1
        } else if (melodyIndex <= 0) {
            melodyIndex = 0; melodyStep = 1
        }
        return downIds[melodyIndex]
    }

    /**
     * 0 for an isolated keystroke, 1 in a fast burst. Average of the last few inter-key
     * intervals mapped linearly between 180 ms (rest) and 80 ms (full burst).
     */
    private fun recordKeyDownAndComputeFlow(): Float {
        val now = SystemClock.elapsedRealtime()
        recentDownTimes.addLast(now)
        while (recentDownTimes.size > SPEED_WINDOW) recentDownTimes.removeFirst()
        if (recentDownTimes.size < 3) return 0f
        val times = recentDownTimes.toList()
        var sum = 0L
        for (i in 1 until times.size) sum += times[i] - times[i - 1]
        val avgSec = sum / 1000.0 / (times.size - 1)
        if (avgSec >= FAST_THRESHOLD) return 0f
        val progress = (FAST_THRESHOLD - avgSec) / (FAST_THRESHOLD - VERY_FAST_FLOOR)
        return progress.coerceIn(0.0, 1.0).toFloat()
    }

    private fun play(id: Int, gain: Float, ducksOthers: Boolean, releaseSec: Double) {
        if (id !in loaded) return
        if (ducksOthers) duckEverything(releaseSec)
        val v = (gain * volume).coerceIn(0f, 1f)
        val stream = pool.play(id, v, v, /* priority */ 1, /* loop */ 0, /* rate */ 1f)
        if (stream != 0 && ducksOthers) {
            // Only key-downs are tracked for ducking: up clicks are short and quiet,
            // and tracking them doubles the bookkeeping for no audible gain.
            ducking.add(DuckingVoice(stream, v, releaseSec))
            startDuckTimerIfNeeded()
        }
    }

    /** Each new keydown fades whatever is still ringing so the newest click dominates. */
    private fun duckEverything(releaseSec: Double) {
        // Restart the fade on every voice with the new (speed-tracked) release.
        val replaced = ducking.map { v ->
            val progress = (v.elapsed / v.releaseSec).coerceIn(0.0, 1.0)
            val currentLevel = v.startVolume * 0.5f * (1 + cos(PI * progress)).toFloat()
            DuckingVoice(v.streamId, currentLevel, releaseSec)
        }
        ducking.clear()
        ducking.addAll(replaced)
    }

    private fun startDuckTimerIfNeeded() {
        handler.removeCallbacks(duckTick)
        lastDuckTick = SystemClock.elapsedRealtime()
        handler.postDelayed(duckTick, DUCK_TICK_MS)
    }

    private fun tickDucking() {
        val now = SystemClock.elapsedRealtime()
        val dt = (now - lastDuckTick) / 1000.0
        lastDuckTick = now
        val it = ducking.iterator()
        while (it.hasNext()) {
            val voice = it.next()
            voice.elapsed += dt
            val progress = (voice.elapsed / voice.releaseSec).coerceIn(0.0, 1.0)
            // Raised cosine: flat at the start so the note keeps its identity,
            // steep in the middle, flat again into silence.
            val next = voice.startVolume * 0.5f * (1 + cos(PI * progress)).toFloat()
            if (progress >= 1.0 || next <= DUCK_FLOOR) {
                pool.setVolume(voice.streamId, 0f, 0f)
                it.remove()
            } else {
                pool.setVolume(voice.streamId, next, next)
            }
        }
        if (ducking.isNotEmpty()) handler.postDelayed(duckTick, DUCK_TICK_MS)
    }

    private fun cancelDucking() {
        handler.removeCallbacks(duckTick)
        ducking.clear()
    }

    companion object {
        private const val TAG = "KlackSound"
        private const val MAX_STREAMS = 24
        private const val MAX_VARIANTS = 8

        private const val SPEED_WINDOW = 6
        private const val FAST_THRESHOLD = 0.18   // seconds between keys
        private const val VERY_FAST_FLOOR = 0.08

        private const val DUCK_RELEASE_SLOW = 0.13
        private const val DUCK_RELEASE_FAST = 0.045
        private const val DUCK_FLOOR = 0.05f
        private const val DUCK_TICK_MS = 8L

        /** Deliberately downward: a burst should settle into texture, not stack louder. */
        fun burstGain(flow: Float): Float = 1f - 0.28f * flow.coerceIn(0f, 1f)

        private fun releaseFor(flow: Float): Double =
            DUCK_RELEASE_SLOW + (DUCK_RELEASE_FAST - DUCK_RELEASE_SLOW) * flow
    }
}
