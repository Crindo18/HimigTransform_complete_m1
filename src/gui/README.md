# `src/gui/`

## `HimigTransformApp.mlapp` is missing on purpose

App Designer files are binary containers that can only be created by App
Designer itself. It is generated at **Milestone M6** by running:

```matlab
appdesigner
```

and saving as `src/gui/HimigTransformApp.mlapp`.

## Rules for this folder

1. **One owner.** `.mlapp` cannot be merged by Git. Two people editing it in
   the same week means one of them loses work (risk R7). Assign the app to a
   single group member; everyone else contributes through `AppController.m`
   and `src/viz/`.

2. **The app holds no logic.** Widget callbacks call methods on
   `AppController` and nothing else. If a callback body grows past a couple of
   lines, that logic belongs in the controller where it can be tested.

3. **Plots come from `src/viz/`.** `plotConstellation` and
   `plotOffsetHistogram` take an axes handle precisely so the GUI and the
   paper render identically.

## Required panels (M6 exit criteria)

- Load file / record / play
- Waveform
- Spectrogram with constellation overlay
- Time-offset histogram
- Ranked results table
- Baseline ↔ enhanced toggle
- Match time readout
- Accept / reject badge (open-set decision)

Cold start to first identification: **under 30 s** on the demo laptop.
Both modes switchable **without restarting**.
Keep the pre-recorded WAV fallback set ready in case the venue microphone
fails (risk R11).
