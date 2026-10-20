package com.klack.keyboard

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.SeekBar
import android.widget.Spinner
import android.widget.TextView
import android.view.inputmethod.InputMethodManager
import androidx.appcompat.app.AppCompatActivity

/** Pick a pack, set the volume, and (the part users actually get stuck on) enable + select the IME. */
class SettingsActivity : AppCompatActivity() {

    private lateinit var settings: KlackSettings
    private lateinit var sound: ClickSoundEngine
    private lateinit var status: TextView
    private var packs: List<String> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        settings = KlackSettings(this)
        sound = ClickSoundEngine(this).also { it.volume = settings.volume }

        status = findViewById(R.id.status)

        findViewById<Button>(R.id.enable_button).setOnClickListener {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        findViewById<Button>(R.id.select_button).setOnClickListener {
            (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).showInputMethodPicker()
        }

        packs = KlackSettings.availablePacks(this)
        val spinner = findViewById<Spinner>(R.id.pack_spinner)
        spinner.adapter = ArrayAdapter(
            this, android.R.layout.simple_spinner_dropdown_item, packs.map(KlackSettings::label)
        )
        val current = packs.indexOf(settings.pack).takeIf { it >= 0 } ?: 0
        spinner.setSelection(current, false)
        if (packs.isNotEmpty()) sound.loadPack(packs[current])
        spinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                val pack = packs[position]
                if (pack != settings.pack) {
                    settings.pack = pack
                    sound.loadPack(pack)
                    // Give SoundPool a beat to decode before the demo plays.
                    spinner.postDelayed({ sound.preview() }, 250)
                }
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        findViewById<Button>(R.id.preview_button).setOnClickListener { sound.preview() }

        val seek = findViewById<SeekBar>(R.id.volume_seek)
        seek.progress = (settings.volume * 100).toInt()
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    val v = progress / 100f
                    settings.volume = v
                    sound.volume = v
                }
            }
            override fun onStartTrackingTouch(bar: SeekBar?) {}
            override fun onStopTrackingTouch(bar: SeekBar?) { sound.keyDown(false); sound.keyUp(false) }
        })
    }

    override fun onResume() {
        super.onResume()
        refreshStatus()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) refreshStatus()
    }

    private fun refreshStatus() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        val myId = "$packageName/.${KlackInputMethodService::class.java.simpleName}"
        val enabled = imm.enabledInputMethodList.any { it.id == myId || it.packageName == packageName }
        val selectedId = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
        val selected = selectedId != null && selectedId.startsWith("$packageName/")
        status.setText(
            when {
                selected -> R.string.status_active
                enabled -> R.string.status_enabled
                else -> R.string.status_not_enabled
            }
        )
    }

    override fun onDestroy() {
        sound.release()
        super.onDestroy()
    }
}
