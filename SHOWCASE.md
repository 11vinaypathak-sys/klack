# Showcasing Klack

Everything here regenerates from source — if the design changes, rerun the
commands and the assets update. Nothing is hand-cropped.

## Assets

| File | Size | Use |
|---|---|---|
| `docs/social/behance-cover.png` | 1600×1000 | Behance project cover |
| `docs/social/linkedin.png` | 1200×627 | LinkedIn link preview / post image |
| `docs/social/instagram-square.png` | 1080×1080 | Instagram feed |
| `docs/social/instagram-portrait.png` | 1080×1350 | Instagram feed (taller = more screen space) |
| `docs/images/demo.mp4` | 1120×800 | The moving demo — post this, not a still |
| `docs/images/demo.gif` | 440px | README / anywhere GIF autoplays |
| `docs/images/themes/*.png` | 4 files | The four colour schemes, side by side |
| `docs/images/panel.png`, `panel-mixer.png` | 2× | Clean panel shots |

Regenerate everything:

```bash
swift build -c release --product Klack

# Panel stills
KLACK_RENDER_TEST=docs/images/panel.png ./.build/release/Klack
KLACK_RENDER_MIXER=1 KLACK_RENDER_TEST=docs/images/panel-mixer.png ./.build/release/Klack

# Each theme
for TH in AMBER ICE PHOSPHOR SYNTH; do
  KLACK_THEME=$TH KLACK_RENDER_TEST="docs/images/themes/$(echo $TH | tr 'A-Z' 'a-z').png" \
    ./.build/release/Klack
done

# Social canvases (caption optional)
KLACK_SOCIAL=1080x1080 KLACK_CAPTION="your caption" \
  KLACK_RENDER_TEST=docs/social/instagram-square.png ./.build/release/Klack
```

## The one asset you have to make yourself

**A screen recording of you actually typing.** Everything above is rendered
offscreen, which is great for consistency but means nothing shows the app
*being used*. The sound is the whole point and none of these assets have any.

Record with `Cmd+Shift+5`, capture audio, ~30 seconds:

1. Menu bar icon → Open Control Panel Window
2. Type a sentence at normal speed — the waveform moves, the backlight pulses,
   the meter climbs
3. Type a fast burst — the meter fills and the volume lifts
4. Click through CLICKY → CREAMY → THOCKY; the whole panel changes colour and
   the sound changes with it
5. Open the MIXER drawer, drag a knob, hit Preview
6. Drag the volume meter

Keep it tight. The colour-change-on-pack-switch is the strongest single moment —
lead with it if you cut a shorter version.

---

## Behance

Behance rewards depth, so use `CASE_STUDY.md` as the body — it's already
structured for this. Suggested order:

1. **Cover** — `behance-cover.png`
2. **The demo video**
3. **The problem** — why a synthesised click sounds fake, and what modal
   synthesis does about it
4. **The four themes** — the strongest visual moment
5. **Process** — the Figma-first UI work, and the render harness that caught
   bugs code review missed
6. **The engineering** — real-time DSP, the audio graph, the import pipeline
7. **Credits** — DSEG7 under SIL OFL; sound packs from Pixabay/Freesound

Tags: `ui design`, `interaction design`, `skeuomorphism`, `macos`, `audio`,
`swift`, `creative coding`, `y2k`

## LinkedIn

Lead with the engineering, not the aesthetics — that's what travels there.

> I built a macOS app that makes my keyboard sound mechanical. Then I got
> carried away.
>
> Klack sits in the menu bar and plays a click on every keystroke. The
> interesting part isn't the idea, it's what it took to make it not sound fake:
>
> → Every click is **synthesised in real time** — decaying resonant modes at
> inharmonic ratios, a noise transient, and a low-frequency body resonance.
> Filtered noise alone reads as static, not as a struck object.
> → A 24-voice audio graph with a limiter, because fast typing summed to
> clipping and the obvious fix (dropping clicks) was the wrong one.
> → 0.165 ms to render a click, measured — that's what makes the live mixer
> feel instant.
> → A headless render harness that draws the UI offscreen to PNG, which caught
> three bugs code review didn't: an upside-down knob, a texture artifact, and
> an inverted panel.
>
> The UI is a hardware faceplate drawn entirely in Core Graphics — no image
> assets. Four colour schemes, and switching sound packs restyles the whole
> instrument.
>
> Built with Claude. Case study and code in comments.

Attach `linkedin.png` or the video. Put the repo link in the first comment,
not the post.

## Instagram

Visual-first. Carousel works better than a single image.

**Slide order:** demo video → the four themes → the mixer drawer open → a
close-up of the display → one line about how it's made.

Caption:

> Made my keyboard sound mechanical 🎛️
>
> Every click is synthesised from scratch — no samples. The panel is drawn
> pixel by pixel in code, no images. Four colour schemes, and the whole thing
> changes colour when you switch sounds.
>
> Sound on 🔊
>
> #creativecoding #uidesign #skeuomorphism #y2kaesthetic #macos #swift
> #interactiondesign #mechanicalkeyboard #generativeart #audiodesign
> #productdesign #uiux

Sound on is doing real work in that caption — the app is *about* sound and
Instagram mutes by default.

## What to be honest about

Worth saying plainly wherever you post it, because someone will ask:

- **It was built with Claude**, over a session. That's a more interesting story
  right now than pretending otherwise, and the case study documents where the
  AI was wrong — a rotary convention that was off by 150°, and a knob texture
  built the wrong way round.
- **The sound packs are licensed recordings** from Pixabay/Freesound, not
  original field recordings. The *synthesis engine* is original; the sampled
  packs are not.
- **It isn't notarised**, so it won't run on someone else's Mac without them
  bypassing Gatekeeper. It's a portfolio piece, not a distributed app. Say so
  rather than inviting downloads that fail.
