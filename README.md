# HimigTransform

A noise-robust audio fingerprinting system for identifying American and
Original Pilipino Music (OPM) songs from short audio segments.

DSIGPRO Term Project · Group 4 · De La Salle University

---

## Status: M2 complete — 100 songs enrolled, both index backends benchmarked

Audio in, song identified out, on the real 100-song database.

```
preprocess → STFT → peak picking → density cap → combinatorial hashing
          → index (csr | containers.Map) → lookup → offset alignment → scoring
```

**Measured at M2** (100 songs, `baselineConfig`, R2025a):

| | |
|---|---|
| clean 10 s top-1 accuracy | **100.0%** (100/100) |
| enrolment | 13.9 s (budget: 15 min) |
| median match time | **13 ms**, p95 15 ms (budget: 1 s) |
| index | 1.44 M postings, 548 k keys, 12.4 MB |
| peak density | 12.1/s achieved |

**Still stubbed** — everything from M4 onward: `pickPeaksAdaptive`,
`spectralSubtract`, `estimateNoiseSpectrum`, all of `src/eval/`, the plots,
`AppController`, and `s04`–`s08`. Each raises
`HimigTransform:NotImplemented` naming its milestone.

### Two things to settle before M3 freezes the baseline

1. **The density cap is inert.** `Cfg.peaks.densityPerSec = 25` sits above the
   18.2/s geometric ceiling of the 21×21 neighbourhood, so it never binds and
   density is whatever the neighbourhood yields. This matters at M4, where
   both peak pickers run through `enforcePeakDensity` specifically so fixed
   and adaptive are compared at equal peak budget. Run
   `peakBudgetAudit(baselineConfig(), true)` for the full analysis, and see
   `docs/designNotes.md` for the three options.

2. **The SNR grid** is currently the proposal's `[Inf 10 5 0]`. The extended
   `[Inf 20 15 10 5 0]` is strictly additive and locates the knee of the
   accuracy curve.

Both change the baseline, so they are cheap now and expensive after
`git tag v0.1-baseline-frozen`.

---

## Setup

**MATLAB R2025a.** Agreed for the whole group.

> Agreed version: **R2025a** — do not mix releases.

Required: Signal Processing Toolbox (`resample`).
Optional, with fallbacks: Audio Toolbox, Image Processing Toolbox,
Statistics and Machine Learning Toolbox, Parallel Computing Toolbox.
See blueprint §1.2 — every toolbox call goes behind `requireToolbox` so a
missing licence fails at setup with a readable message rather than at
integration week with an undefined function.

```matlab
cd /path/to/HimigTransform
setupPaths        % once per session
runTests          % should print MERGE GATE: OPEN
```

Then populate `data/` — see [`data/README.md`](data/README.md).

---

## Run order

Each script is idempotent and can be re-run safely.

```matlab
s01_ingest          % M0  raw audio -> 8 kHz mono + catalog.csv
s02_prepareNoise    % M0  DEMAND -> data/noise/
s03_enroll          % M2  fingerprints + BOTH indexes
s04_buildQueries    % M3  deterministic query manifest
s05_tuneThresholds  % M5  tau, rho  -- DEV SPLIT ONLY
s06_runEvaluation   % M7  full factorial -- TEST SPLIT
s07_makeFigures     % M7
s08_makeTables      % M7
```

---

## Milestones

| | Milestone | Exit criterion |
|---|---|---|
| ~~**M0**~~ | ~~Skeleton and data spine~~ | Done |
| ~~**M1**~~ | ~~Vertical slice~~ | Done — interfaces frozen |
| ~~**M2**~~ | ~~Baseline at full scale~~ | **Done** — 100 songs, 100% clean top-1, 13.9 s enrolment, 13 ms median match, both backends benchmarked |
| **M3** | Evaluation harness | Full baseline grid runs unattended; then `git tag v0.1-baseline-frozen` |
| **M4** | Enhancement 1 | ≥10 pp gain at 0 dB on **dev**; ≤2 pp regression on clean |
| **M5** | Enhancement 2 + open-set | Gain at 3 s; ROC over holdout; `tau`/`rho` frozen in config |
| **M6** | GUI | Cold start to first identification < 30 s; both modes without restart |
| **M7** | Full run, figures, paper | Every number traces to a committed script and a results file |
| **M8** | Hardening and freeze | Fresh-clone rehearsal reproduces the figures; `git tag v1.0-final` |

---

## Three rules that are easy to break and expensive to fix

1. **The test split is touched exactly once, at M7.** All tuning — `alpha`,
   `beta`, `kappaDb`, `freqDecim`, `tau`, `rho` — happens on dev. Tuning on the
   data you report is the most common way a project like this produces a number
   it cannot defend at the panel.

2. **Freeze the baseline before building the enhancements.** `git tag
   v0.1-baseline-frozen` at M3. Every later comparison points at that tag.

3. **One owner for `HimigTransformApp.mlapp`.** It is a binary container; Git
   cannot merge it. Everyone else contributes through `src/gui/AppController.m`
   and `src/viz/`.

---

## Layout

```
config/        Cfg struct, baseline/enhanced configurations, tag generation
src/util/      audio I/O, normalisation, checksums, logging, toolbox gating
src/io/        ingest, catalog, noise bank, fingerprint cache
src/features/  preprocessing, STFT, spectral subtraction
src/fingerprint/ peak picking, density capping, combinatorial hashing
src/db/        enrolment, index build (csr + map backends), lookup, pruning
src/match/     offset alignment, scoring, open-set decision
src/eval/      query manifest, SNR mixing, experiment runner, metrics, stats
src/viz/       every figure in the paper, plus the GUI's plots
src/gui/       AppController (logic) + HimigTransformApp.mlapp (view, at M6)
scripts/       s01..s08, the numbered pipeline
tests/         runTests + six contract tests
docs/          designNotes.md — decisions and why
```

**Naming trap:** never create `src/features/stft.m`. It shadows the Signal
Processing Toolbox function for the whole session and breaks the very test
meant to validate your implementation. Same for `spectrogram.m`, `resample.m`,
`hamming.m`. Verb-noun camelCase (`computeSTFT`, `resampleAudio`) sidesteps it.

---

## Work split

Interfaces freeze at M1; after that these five streams run in parallel against
the stubs.

| Stream | Owns | Weight |
|---|---|---|
| A — Data & I/O | `src/io/`, `src/util/`, catalog, noise bank | M0, M2 |
| B — DSP front end | `src/features/`, peak picking, spectral subtraction | M1, M4 |
| C — Fingerprint & index | `src/fingerprint/`, `src/db/`, both backends | M1, M2, M5 |
| D — Matching & evaluation | `src/match/`, `src/eval/`, `src/viz/`, statistics | M3, M5, M7 |
| E — GUI & integration | `src/gui/`, `scripts/`, test harness, paper figures | M6, M7, M8 |

Everyone writes tests for their own module. Green `runTests` is the merge gate.

---

## Attribution

Environmental noise: **DEMAND** (Diverse Environments Multichannel Acoustic
Noise Database), CC BY-SA 3.0. Cite it in the paper.
