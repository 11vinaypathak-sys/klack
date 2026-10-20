package com.klack.keyboard

import android.content.Context
import android.content.SharedPreferences

/** The two user settings, persisted in SharedPreferences and shared by the IME and the settings screen. */
class KlackSettings(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("klack", Context.MODE_PRIVATE)

    var pack: String
        get() = prefs.getString(KEY_PACK, DEFAULT_PACK) ?: DEFAULT_PACK
        set(value) = prefs.edit().putString(KEY_PACK, value).apply()

    /** 0..1, applied on top of the device media volume. */
    var volume: Float
        get() = prefs.getFloat(KEY_VOLUME, DEFAULT_VOLUME).coerceIn(0f, 1f)
        set(value) = prefs.edit().putFloat(KEY_VOLUME, value.coerceIn(0f, 1f)).apply()

    fun registerListener(l: SharedPreferences.OnSharedPreferenceChangeListener) =
        prefs.registerOnSharedPreferenceChangeListener(l)

    fun unregisterListener(l: SharedPreferences.OnSharedPreferenceChangeListener) =
        prefs.unregisterOnSharedPreferenceChangeListener(l)

    companion object {
        const val KEY_PACK = "pack"
        const val KEY_VOLUME = "volume"
        const val DEFAULT_PACK = "real_clicky"
        const val DEFAULT_VOLUME = 0.8f

        /** Packs are any assets/profiles/<name>/ folder that has the first down sample. */
        fun availablePacks(context: Context): List<String> {
            val am = context.assets
            val names = am.list("profiles")?.toList().orEmpty()
            return names.filter { name ->
                am.list("profiles/$name")?.contains("click_down_1.wav") == true
            }.sorted()
        }

        /** "deep_thock" -> "Deep Thock", mirroring the Mac app's labels. */
        fun label(pack: String): String = LABELS[pack]
            ?: pack.split('_').joinToString(" ") { it.replaceFirstChar(Char::uppercase) }

        private val LABELS = mapOf(
            // Recorded from a real board; the three the Mac app ships first.
            "real_clicky" to "Clicky (recorded)",
            "real_creamy" to "Creamy (recorded)",
            "real_thocky" to "Thocky (recorded)",
            "creamy" to "Creamy",
            "deep_thock" to "Thocky",
            "clacky" to "Clacky",
            "poppy" to "Poppy",
            "clicky" to "Clicky",
            "the_bench" to "The Bench",
            "vintage" to "Vintage",
            "airy" to "Airy",
        )
    }
}
