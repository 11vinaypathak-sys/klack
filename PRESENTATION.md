# Presenting Klack — Project Structure & Content Plan

This is the plan for turning Klack into a published showcase, built from
actual patterns in how "AI-built" projects get shared right now — not
guesses about what should work.

## What the research actually found

Three sourced patterns, not vibes:

1. **The hook is a specific, checkable claim, not a vague one.**
   ["I built a fully working app in 2 hours"](https://mizko.substack.com/p/building-apps-with-ai) beats "I built an app
   recently." Precision reads as evidence, not boasting — because it's
   falsifiable. This is exactly why we checked the git timestamps before
   writing anything: **"one day" would have been the wrong kind of specific
   — precise, and false.** "Built over a weekend" is precise *and* true.

2. **Build-in-public credibility comes from the mess, not the polish.**
   [Every update, milestone, and learning is content](https://buildinpublichub.substack.com/sitemap/2025) — the pattern that
   performs is documenting real friction, not a highlight reel. We have
   unusually good material for this because it's all *true*: a rotary
   sweep convention that was off by 150°, a knob that rendered upside-down,
   a texture bug that turned into visible static, and an audio regression
   caught by a self-test built specifically because a silent bug slipped
   past everything else. These are better content than the finished panel.

3. **Technical credibility needs one real anchor, not a feature list.**
   The reveal-that-it-was-AI-built format works when there's a genuine
   technical detail underneath it — not just "I prompted and it worked."
   Klack's anchor is unusually strong and slightly unusual for this genre:
   **the AI built a tool to check its own work**, because it kept shipping
   broken UI it couldn't see. That's a different story than "AI wrote my
   code" — it's "AI had a blind spot and built the fix for its own blind
   spot." That's the detail worth leading with, not the glossy plastic.

Source citations: [Substack build logs](https://mizko.substack.com/p/building-apps-with-ai) ·
[Build In Public conventions](https://buildinpublichub.substack.com/p/build-in-public-community-edition-1-aug-2021-728614) ·
[AutoTweet's 2026 build-in-public guide](https://www.autotweet.io/blog/build-in-public-on-x-twitter-2026)

## The project, structured as components

Treat "showcase Klack" as five separate deliverables, not one post. Each
has a different job:

| Component | Job | Status |
|---|---|---|
| **The demo** (video/GIF) | Prove it's real and it sounds good | Rendered assets exist; the one with your voice/typing doesn't yet — see below |
| **The reveal post** (LinkedIn/Instagram) | Get attention, one honest hook | Drafted below |
| **The build log** (Twitter/X thread or LinkedIn carousel) | The "mess" — bugs found, wrong turns, fixes | Drafted below, from real material |
| **The case study** (Behance) | Depth, for people who click through | Already written — `CASE_STUDY.md` |
| **The repo** (GitHub) | Where credibility gets checked | Already clean — 15 commits, real history, self-tests |

## The one true fact to lead with

**Built over a weekend** (Aug 15→16, verifiable from `git log`), starting
from "make my keyboard click" and escalating into a real-time DSP
synthesis engine with a hand-drawn UI. That escalation — small ask,
scope creep, ended up somewhere nobody planned — is itself the story
beat that makes this relatable rather than a flex.

---

## Draft: The reveal post (LinkedIn)

```
I asked Claude to make my keyboard sound mechanical.

By the end of the weekend it had built a real-time audio synthesis
engine, a hand-drawn skeuomorphic control panel, and — this is the part
I didn't see coming — a tool to check its own visual work, because it
kept shipping broken UI it couldn't see.

The synthesis part first: a synthesized click made from pure noise
sounds like static, not a keyboard. The fix was modal synthesis —
modeling the click as a handful of decaying resonant tones at
inharmonic frequencies, the same technique used for realistic drum
and bell sounds. Detune two of those tones slightly and they beat
against each other the way a real struck object does. That's the
difference between "fake click" and "click."

The UI is where it got interesting. Claude was designing a control
panel — knobs, an LED meter, a backlit display — entirely in code, with
no way to see what it was drawing. So it built a render harness: a
headless mode that draws the panel offscreen to a PNG, so it could
actually look at its own output instead of guessing.

That's how we caught a knob rendering upside-down, a texture bug that
looked like static, and a seam across a button face that only showed up
at 4x zoom. None of those were visible in the code. All of them were
obvious in a screenshot.

It also once shipped a silent-audio regression that got past everything
— clean build, working UI, no sound. So now there's a second self-test
that actually schedules a buffer and checks the app can make noise
before I trust a change. I proved it catches the bug by putting the bug
back and watching the test fail.

Repo, case study, and the version with real bugs still in the commit
history: [link]

Built with Claude.
```

## Draft: The build log (thread/carousel — the "mess" content)

Five short beats, each one true and each one checkable in the commit
history if anyone looks:

```
1/ Started with: "make my keyboard sound mechanical." 
   Ended up with: a synthesis engine + a hand-drawn UI + two testing
   harnesses I never asked for. Scope crept because it was fun.

2/ First version of the "click" was filtered noise. Sounded like static
   over a speaker, not a keyboard. Real fix: model it as a struck
   object — a few decaying tones at frequencies that don't line up
   neatly, plus a noise transient for the initial hit.

3/ Building the panel, Claude had zero way to see what it was drawing —
   it was writing Core Graphics code blind. So it built a mode that
   renders the whole UI offscreen to a PNG. First screenshot: a volume
   knob lit from the wrong side. Root cause — an image drawn into a
   flipped coordinate space, silently mirrored.

4/ Caught two more the same way: a metal texture that looked like TV
   static (a tiling bug at Retina scale), and a button with a visible
   seam where two gradients met at slightly different points. Neither
   was visible in the code. Both were obvious in a screenshot.

5/ Then it shipped a version with a clean build and totally silent
   audio. Nothing in the visual checks would ever catch that — wrong
   category of bug entirely. Now there's a self-test that actually
   plays a sound and checks the engine is running before anything
   ships. Proved it works by breaking the code on purpose and watching
   the test go red.
```

## Draft: Instagram caption

Shorter, sound-forward, since the whole point is audio:

```
Made my keyboard sound mechanical this weekend 🎛️

No samples — every click is synthesized from scratch. No images — the
whole panel is drawn in code. Four colour schemes, and the panel
restyles itself when you switch sounds.

Built with Claude, bugs and all — link in bio for the version where you
can see it screw up an upside-down knob and fix it.

Sound on 🔊
#creativecoding #uidesign #buildinpublic #vibecoding #macos #swift
#audiodesign #y2kaesthetic
```

## What I still can't make for you

Everything above is text I drafted, but the **actual demo clip with your
voice or your typing** is the one asset that has to come from you — see
`SHOWCASE.md` for the shot list. Five platform-sized image exports and a
rendered demo video already exist in `docs/social/` and `docs/images/`;
none of them have you in them, and that's the thing that will make a
stranger actually believe this is real rather than a template.
