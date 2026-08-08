# HimigTransform

A noise-robust audio fingerprinting system for identifying American and
Original Pilipino Music (OPM) songs from short audio segments.

DSIGPRO Term Project · Group 4 · De La Salle University

---

## Status: skeleton (Milestone M0)

The repository structure, configuration layer and test harness are in place.
Every function under `src/` is a **stub with a frozen interface contract** —
the signature and documented behaviour are settled, the body is written at the
milestone named in each file's header.

**Implemented and working**

| | |
|---|---|
| `setupPaths.m` | Path setup, working-folder creation |
| `config/*.m` | The full `Cfg` struct, both system configurations, tag generation, query-side resolution |
| `tests/runTests.m` | Test runner with the pending/failed distinction |

**Stubbed** — 51 functions across `src/`, 1 controller class, 8 pipeline
scripts. Each raises `HimigTransform:NotImplemented` with its milestone.

---

## Setup

**MATLAB R2021b or newer.** Pin one version for the whole group and record it
here once agreed:

> Agreed version: `_______________` (fill this in)

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
| **M0** | Skeleton and data spine | `runTests` runs; `catalog.csv` built; every processed file verified 8 kHz mono |
| **M1** | Vertical slice — **freeze the interfaces here** | `tSTFT`, `tHashPack`, `tSelfMatch` green on the 5-song toy set, margin > 3 |
| **M2** | Baseline at full scale | 100 songs enrolled; ≥95% top-1 on clean 10 s; enrolment < 15 min; median match < 1 s |
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
