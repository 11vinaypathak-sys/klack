package com.klack.keyboard

import android.content.SharedPreferences
import android.inputmethodservice.InputMethodService
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection

/** Klack as a keyboard: types like a basic QWERTY, sounds like a mechanical board. */
class KlackInputMethodService : InputMethodService(), KeyboardView.Listener,
    SharedPreferences.OnSharedPreferenceChangeListener {

    private lateinit var settings: KlackSettings
    private lateinit var sound: ClickSoundEngine
    private var keyboard: KeyboardView? = null

    override fun onCreate() {
        super.onCreate()
        settings = KlackSettings(this)
        sound = ClickSoundEngine(this).also {
            it.volume = settings.volume
            it.loadPack(resolvePack())
        }
        settings.registerListener(this)
    }

    override fun onDestroy() {
        settings.unregisterListener(this)
        sound.release()
        super.onDestroy()
    }

    /** The saved pack, or the first bundled one if that pack is missing. */
    private fun resolvePack(): String {
        val packs = KlackSettings.availablePacks(this)
        val wanted = settings.pack
        return if (wanted in packs) wanted else packs.firstOrNull() ?: wanted
    }

    override fun onSharedPreferenceChanged(prefs: SharedPreferences?, key: String?) {
        when (key) {
            KlackSettings.KEY_PACK -> sound.loadPack(resolvePack())
            KlackSettings.KEY_VOLUME -> sound.volume = settings.volume
        }
    }

    override fun onCreateInputView(): View =
        KeyboardView(this).also {
            it.listener = this
            keyboard = it
        }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        keyboard?.shiftState = if (shouldAutoCapitalise(info)) KeyboardView.ShiftState.ON
        else KeyboardView.ShiftState.OFF
    }

    private fun shouldAutoCapitalise(info: EditorInfo?): Boolean {
        info ?: return false
        val caps = info.inputType and (InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or
            InputType.TYPE_TEXT_FLAG_CAP_WORDS or InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS)
        if (caps == 0) return false
        val ic = currentInputConnection ?: return false
        return ic.getCursorCapsMode(info.inputType) != 0
    }

    // --- KeyboardView.Listener ---------------------------------------------------------

    override fun onKeyDown(key: KeyboardView.Key) {
        sound.keyDown(isSpace = key.code == KeyboardView.Code.SPACE)
    }

    override fun onKeyUp(key: KeyboardView.Key) {
        val ic: InputConnection? = currentInputConnection
        when (key.code) {
            KeyboardView.Code.CHAR, KeyboardView.Code.SPACE -> {
                keyboard?.textFor(key)?.let { ic?.commitText(it, 1) }
                if (key.code == KeyboardView.Code.SPACE || key.char == '.') {
                    // Re-evaluate sentence-start capitalisation after a word boundary.
                    if (shouldAutoCapitalise(currentInputEditorInfo) &&
                        keyboard?.shiftState == KeyboardView.ShiftState.OFF
                    ) keyboard?.shiftState = KeyboardView.ShiftState.ON
                }
            }
            KeyboardView.Code.BACKSPACE -> deleteOne(ic)
            KeyboardView.Code.ENTER -> handleEnter(ic)
            KeyboardView.Code.SHIFT, KeyboardView.Code.SYMBOLS, KeyboardView.Code.LETTERS -> {}
        }
        sound.keyUp(isSpace = key.code == KeyboardView.Code.SPACE)
    }

    override fun onBackspaceRepeat() {
        deleteOne(currentInputConnection)
        // Held backspace is one key event per deletion on a real board too.
        sound.keyDown(isSpace = false)
    }

    /** A DEL key event respects selections and composing text; deleteSurroundingText does not. */
    private fun deleteOne(ic: InputConnection?) {
        ic ?: return
        val selected = ic.getSelectedText(0)
        if (!selected.isNullOrEmpty()) {
            ic.commitText("", 1)
        } else {
            sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)
        }
    }

    private fun handleEnter(ic: InputConnection?) {
        val info = currentInputEditorInfo
        val options = info?.imeOptions ?: 0
        val action = options and EditorInfo.IME_MASK_ACTION
        val multiline = (info?.inputType ?: 0) and InputType.TYPE_TEXT_FLAG_MULTI_LINE != 0
        val noEnterAction = options and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0
        if (!multiline && !noEnterAction && action != EditorInfo.IME_ACTION_NONE &&
            action != EditorInfo.IME_ACTION_UNSPECIFIED
        ) {
            ic?.performEditorAction(action)
        } else {
            sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
        }
    }
}
