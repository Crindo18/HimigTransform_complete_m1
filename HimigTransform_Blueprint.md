# HimigTransform — Engineering Blueprint

**Project:** Noise-robust audio fingerprinting for American + OPM song identification
**Course:** DSIGPRO Term Project (Group 4)
**Platform:** MATLAB
**Document status:** Architecture spec — read before writing code. No implementations here by design; interfaces and contracts only.

---

## 0. The four decisions that shape everything else

Before the detail, these are the choices that are expensive to reverse. Everything downstream follows from them.

**D1 — Build the evaluation harness *before* the enhancements.**
Success criterion #1 is "≥10 percentage points over baseline at 0 dB SNR." You cannot claim a gain you did not measure against a frozen reference. The harness (query generation, noise mixing, metrics, plots) is Milestone 3; the enhancements are Milestones 4–5. Freeze and git-tag the baseline before touching it. If you build the enhancements first, you will spend the last week reconstructing a baseline you have already contaminated.

**D2 — Do not store query WAV files. Store a query *manifest* and synthesise deterministically.**
The full factorial is ~10,800 queries per system. Written to disk that is ~1 GB of audio that cannot go in Git and will drift between group members. Instead store a table of `(songID, startSample, lengthSec, noiseFile, noiseStartSample, targetSNR, seed)` and regenerate the waveform on demand. The manifest is a 500 KB CSV, it is reproducible bit-for-bit, and it removes disk I/O from the inner loop. Export ~30 real WAVs only for the GUI demo and report figures.

**D3 — `containers.Map` is the proposal's stated index, but it will not scale gracefully. Plan the swap now.**
At 100 songs you will generate roughly 4–10 million hash postings across ~3 million distinct keys. A `containers.Map` with `'ValueType','any'` stores each posting list as a separate MATLAB array, each carrying ~100 bytes of header — several hundred MB of overhead, and a build time measured in minutes if you append incrementally (that pattern is O(n²)). Architect the index behind a thin interface (`buildIndex` / `queryIndex`) with **two swappable backends**: `containers.Map` (proposal-faithful, bulk-constructed in one call) and a sorted CSR array index (fast, ~50–100 MB). Benchmark both and report the comparison — a scalability finding is a contribution, not a deviation.

**D4 — Build one index per configuration, not one shared "superset" index.**
It is tempting to enrol once with a maximal target zone and fan-out, then vary only the query side. It does not work cleanly: the hash *encodes* Δt, so a wider database zone adds retrievable postings that also change baseline behaviour, contaminating the comparison. Enrolment is a one-time ~10-minute cost. Build `index_baseline` and `index_enhanced` from the same extraction run, both keyed by a config tag. Clean ablations are worth ten minutes.

---

## 1. Tech Stack

### 1.1 Core

| Component | Choice | Rationale |
|---|---|---|
| Language / runtime | MATLAB R2021b or newer (pin one version for the whole group in `README.md`) | Mandated by the proposal; `movmedian`, `heatmap`, `string`, and modern `accumarray` behaviour all present |
| GUI | MATLAB App Designer (`.mlapp`) | Objective #4; ships with base MATLAB |
| Version control | Git + GitHub (private repo, matching your `DysarthricVCR` setup) | Audio and `.mat` indexes stay out of the repo — see §4.4 |
| Numerics | Base MATLAB (`fft`, `accumarray`, `sortrows`, `ismember`, `movmedian`) | Portability across teammates' licences |

### 1.2 Toolbox dependency policy

**Rule: every toolbox call goes behind a wrapper function with a base-MATLAB fallback.** If one group member's licence lacks a toolbox mid-term, you find out at integration, not at the defence.

| Toolbox | Used for | Required? | Fallback |
|---|---|---|---|
| Signal Processing Toolbox | `resample` (anti-aliased 8 kHz downsample), `spectrogram` (verification only), `hamming` | **Yes**, for `resample` | `hamming` is trivial to hand-write; `resample` can be replaced with `decimate` or a hand-designed FIR + `filtfilt` |
| Audio Toolbox | `audioDeviceReader`, `audioDatastore` | No | `audiorecorder` (base MATLAB) for live capture; `dir` + loop for datastore |
| Image Processing Toolbox | `medfilt2`, `ordfilt2` for the 2-D local-median in adaptive peak picking | No | `movmedian` applied along each dimension (separable approximation) — **default to this** |
| Statistics & ML Toolbox | `confusionmat`, `confusionchart` | No | `accumarray` + `heatmap` (base MATLAB) |
| Parallel Computing Toolbox | `parfor` over enrolment and the evaluation grid | No | `parfor` degrades to serial `for` automatically when unlicensed |

### 1.3 What you deliberately do **not** use

- **`spectrogram()` as the production STFT.** Implement framing + windowing + `fft` by hand. This is a DSP course; the pipeline *is* the deliverable. Keep `spectrogram()` in the test suite as a ground-truth oracle (see `tSTFT.m`, §5).
- **Any deep-learning toolbox.** The research gap explicitly positions this as the lightweight classical alternative. Introducing a network undermines the thesis.
- **File-exchange dependencies.** Everything must run from a clean clone on a lab machine.

### 1.4 External datasets

| Purpose | Source | Notes |
|---|---|---|
| Environmental noise | **DEMAND** (Zenodo) — <cite index="9-1">a 16-channel environmental noise database, licensed CC BY-SA 3.0, distributed as single-channel WAVs at 48 kHz and 16 kHz</cite> | Take the 16 kHz version, channel 01 only, and resample to 8 kHz. <cite index="3-1">Recordings are trimmed to 300 s each.</cite> Map to the proposal's three noise types: **PCAFETER** (<cite index="2-1">a busy office cafeteria</cite>) → café babble; **STRAFFIC** (<cite index="2-1">a busy traffic intersection</cite>) → street traffic; **SPSQUARE** (<cite index="2-1">a public town square with many tourists</cite>) → crowd. Attribute DEMAND in the paper — ShareAlike applies to derivatives you redistribute, so do not ship mixed audio publicly. |
| Music (100 in-DB + 20 holdout) | Group members' own libraries | Treated as read-only local data. `data/raw/**` is gitignored and never redistributed; the repo carries only `catalog.csv` with SHA-256 checksums so members can verify they have identical files. State the academic-use basis in the paper's dataset section. |

---

## 2. Data Models

MATLAB has no database engine, so "schema" here means the on-disk and in-memory contracts. **Every one of these is a frozen interface** — agree on them at Milestone 1 and the five workstreams in §10 can proceed in parallel.

### 2.1 `Cfg` — the configuration struct (single source of truth)

Every function that has a parameter takes it from `Cfg`. No magic numbers in function bodies, ever. `Cfg` is serialised into every index and every results file so any figure can be traced back to the exact settings that produced it.

```
Cfg
├── tag                    char    e.g. 'base_fs8k_w512_d25_F8_dt32'  (derived, see makeConfigTag)
├── seed                   double  RNG seed (default 42)
├── audio
│   ├── fs                 8000    Hz
│   ├── mono               true
│   └── targetRmsDbfs      -20     RMS normalisation target (NOT peak — see §6.1)
├── pre
│   ├── dcRemove           true
│   └── preemphAlpha       0.97    set to 0 to disable; must match on both sides
├── stft
│   ├── winLen             512     samples = 64 ms
│   ├── hop                256     samples = 32 ms (50% overlap) → 31.25 frames/s
│   ├── nfft               512     → 257 bins, Δf = 15.625 Hz
│   └── window             'hamming'
├── peaks
│   ├── mode               'fixed' | 'adaptive'
│   ├── nbhdF              21      bins   (local-max neighbourhood)
│   ├── nbhdT              21      frames
│   ├── densityPerSec      25      target peaks/second (density cap)
│   ├── bandEdgesHz        [0 250 500 1000 2000 4000]
│   └── kappaDb            6       adaptive: dB above local median to admit a peak
├── hash
│   ├── fanout             8       targets per anchor
│   ├── dtMin              1       frames
│   ├── dtMax              32      frames (~1.02 s)
│   ├── dfMaxBins          64      max |f2 - f1| in bins
│   └── freqDecim          1       bin >> log2(freqDecim) before packing (robustness knob)
├── denoise
│   ├── enable             false   QUERY SIDE ONLY
│   ├── alpha              2.0     over-subtraction factor
│   ├── beta               0.02    spectral floor
│   └── noiseFrameFrac     0.10    fraction of lowest-energy frames used for the noise estimate
├── shortQuery
│   ├── enable             false
│   ├── thresholdSec       5
│   ├── fanout             20
│   └── dtMax              64
├── match
│   ├── offsetTolFrames    1       ±1 frame smoothing of the offset histogram
│   ├── maxPostingsPerHash 500     prune non-discriminative hashes (see §6.5)
│   ├── tau                0.02    normalised-score accept threshold (TUNED ON DEV)
│   └── rho                1.50    top1/top2 margin threshold (TUNED ON DEV)
└── eval
    ├── lengthsSec         [3 5 10]
    ├── snrDb              [Inf 10 5 0]
    ├── noiseTypes         {'cafe','traffic','crowd'}
    └── repsPerSong        3
```

### 2.2 `catalog.csv` — the song table

One row per audio file. This is the closest thing you have to a relational table; keep it flat and human-readable.

| Column | Type | Notes |
|---|---|---|
| `songID` | uint16 | Primary key, 1…N. **Never reused, never renumbered.** |
| `title` | string | |
| `artist` | string | |
| `repertoire` | categorical | `american` \| `opm` |
| `role` | categorical | `db` (in the 100) \| `holdout` (the 20 open-set songs) |
| `split` | categorical | `dev` \| `test` — assigned at the **song** level, see §8.2 |
| `year` | uint16 | Optional; useful for the "several decades" claim |
| `sourcePath` | string | Path to the original file, relative to `data/raw/` |
| `procPath` | string | Path to the 8 kHz mono WAV, relative to `data/processed/` |
| `durationSec` | double | Of the processed file |
| `sha256` | string | Checksum of the **processed** file — the reproducibility anchor |

### 2.3 Fingerprint cache — `db/fingerprints/<cfgTag>/song_%04d.mat`

Per-song, so that re-enrolling after a code change is incremental rather than total.

```
peaks.tIdx      uint32 [P x 1]   frame index of each constellation peak
peaks.fIdx      uint16 [P x 1]   bin index
peaks.magDb     single [P x 1]   kept for figures/diagnostics only
hashes.h        uint32 [H x 1]   packed 32-bit code
hashes.t1       uint32 [H x 1]   anchor frame index
meta.songID, meta.cfgTag, meta.nFrames, meta.builtOn
```

### 2.4 Index — `db/index_<cfgTag>.mat`

**Backend A — CSR (recommended default).** Postings sorted and grouped by hash; lookup is a binary search plus a range expansion, fully vectorised.

```
Idx.backend      'csr'
Idx.cfgTag       char
Idx.cfg          struct              full Cfg snapshot
Idx.hashKeys     uint32 [K x 1]      sorted, unique
Idx.bucketPtr    uint32 [K+1 x 1]    CSR offsets; postings for key k are bucketPtr(k):bucketPtr(k+1)-1
Idx.songID       uint16 [N x 1]      postings, grouped by hash
Idx.t1           uint32 [N x 1]      postings, grouped by hash
Idx.nSongs       double
Idx.stats        struct              nHashes, nDistinct, prunedKeys, meanPostingLen, buildSec, bytes
Idx.builtOn      datetime
Idx.matlabVer    char
```

**Backend B — `containers.Map` (proposal-faithful).** Same public interface, different storage:

```
Idx.backend  'map'
Idx.map      containers.Map('KeyType','uint32','ValueType','any')
             key   = packed hash
             value = uint32 [m x 2] of [songID, t1]
```

> **Build it in one shot.** Assemble a flat `(hash, songID, t1)` array, `sortrows` by hash, split into a cell array with `mat2cell` on run-lengths, then call the `containers.Map(keys, values)` constructor **once**. Never `M(key) = [M(key); newRow]` in a loop.

Memory budget for planning (D = 25 peaks/s, avg song 210 s, 100 songs):

| Config | Hashes/s | Postings | CSR bytes | `containers.Map` bytes (est.) |
|---|---|---|---|---|
| Baseline (F=8) | 200 | ~4.2 M | ~45 MB | ~350 MB+ |
| Enhanced (F=20) | 500 | ~10.5 M | ~110 MB | ~800 MB+ |

### 2.5 `queryManifest.csv` — the evaluation query table

Per D2, this *is* the query set. Waveforms are synthesised from it on demand.

| Column | Type | Notes |
|---|---|---|
| `queryID` | uint32 | Primary key |
| `songID` | uint16 | Ground truth; the row's `role` in `catalog` decides in-DB vs holdout |
| `repertoire` | categorical | Denormalised from catalog for easy grouping |
| `split` | categorical | `dev` \| `test` |
| `lengthSec` | double | 3 / 5 / 10 |
| `startSample` | uint32 | Excerpt offset in the processed file |
| `rep` | uint8 | Replicate index 1…`repsPerSong` |
| `noiseType` | categorical | `none` \| `cafe` \| `traffic` \| `crowd` |
| `noiseFile` | string | e.g. `PCAFETER_ch01_8k.wav` |
| `noiseStartSample` | uint32 | |
| `targetSnrDb` | double | `Inf` for clean |
| `seed` | uint32 | Per-query seed; makes each row independently reproducible |

**Invariant:** the *same* `(songID, lengthSec, rep, startSample)` tuple appears once per noise condition. That gives you a **paired design** — the same excerpt heard clean and at 0 dB, by both systems — which is what licenses McNemar's test in §8.4.

### 2.6 `results/raw/results_<system>_<timestamp>.parquet|csv` — long-format results

One row per (query × system). Long format, not wide — every figure is then a `groupsummary` away.

| Column | Type |
|---|---|
| `queryID`, `songID`, `repertoire`, `split`, `lengthSec`, `noiseType`, `targetSnrDb` | (joined from manifest) |
| `system` | `baseline` \| `enh1` \| `enh2` \| `enhanced` |
| `cfgTag` | char |
| `pred1`, `score1`, `pred2`, `score2` | top-2 songID and raw aligned counts |
| `normScore` | `score1 / nQueryHashes` |
| `margin` | `score1 / max(score2,1)` |
| `accepted` | logical (post-threshold) |
| `correct` | logical (`pred1 == songID` for in-DB rows) |
| `nQueryHashes`, `nCandidateSongs` | diagnostics |
| `tMatchSec`, `tHashSec`, `tTotalSec` | timing |

---

## 3. Algorithm Specification

This is the contract the code must satisfy. Numbers are derived, not guessed — carry these into the paper's methodology section.

### 3.1 Time–frequency grid

```
fs = 8000 Hz
winLen = 512 samples = 64.0 ms
hop    = 256 samples = 32.0 ms      → frame rate = 31.25 frames/s
nfft   = 512                        → 257 usable bins, Δf = 15.625 Hz
```

A 3 s query is **93 frames**; a 10 s query is **312 frames**. A 3.5-minute song is ~6,560 frames.

### 3.2 Hash packing (32-bit, per the proposal)

```
bits 31..23   f1   anchor bin        (9 bits, 0..511; only 0..256 used)
bits 22..14   f2   target bin        (9 bits)
bits 13..0    Δt   target − anchor   (14 bits, 0..16383; only 1..64 used)
```

Pack with integer arithmetic on `uint32`: `h = uint32(f1)*2^23 + uint32(f2)*2^14 + uint32(dt)`. Maximum value `511*2^23 + 511*2^14 + 16383 = 4,294,967,295` — exactly `intmax('uint32')`, so the layout is tight and lossless. `unpackHash` must be an exact inverse; that is a unit test (§5).

> **Robustness knob to ablate.** At `freqDecim = 1` a peak that shifts by one bin (15.6 Hz) under noise produces a completely different hash. `freqDecim = 2` (≈31 Hz resolution) trades discriminability for tolerance to spectral smearing. Run this as an ablation at Milestone 4 rather than guessing — it is a cheap paragraph of results.

### 3.3 Peak picking

**Baseline (`mode='fixed'`).** A bin is a peak if it is the maximum over a `nbhdF × nbhdT` neighbourhood and exceeds a global magnitude floor. Then enforce density: within each 1-second window and each of the 5 frequency bands, keep the top-K peaks such that the total rate ≈ `densityPerSec`.

> Two non-obvious requirements. **(a) Cap density per second, not per song** — otherwise a 6-minute track dominates the index and a 2-minute track is under-represented. **(b) Cap per band** — without band-wise selection, all peaks collapse into the bass region where music has most of its energy, and the constellation loses the mid-frequency structure that actually discriminates songs.

**Enhanced (`mode='adaptive'`, Enhancement 1b).** Replace the global floor with a *local* one: admit a peak only if its magnitude exceeds the local median spectral magnitude within its neighbourhood by `kappaDb`. Compute the local median with `movmedian` along frequency then along time (separable approximation; use `medfilt2` if IPT is available and benchmark the difference once). The density cap still applies afterwards. The intent is that peak density stays roughly constant across SNR — **make that a measured plot, not an assertion.** "Peaks/second vs SNR, baseline vs adaptive" is one of your strongest figures because it shows the mechanism, not just the outcome.

### 3.4 Combinatorial hashing

For each anchor peak `a`, take targets `b` where `dtMin ≤ t_b − t_a ≤ dtMax` and `|f_b − f_a| ≤ dfMaxBins`, keep the nearest `fanout` of them by time, and emit `(pack(f_a, f_b, Δt), t_a)`.

Sanity check on the short-query mode: a 3 s query at 25 peaks/s holds ~75 peaks, so C(75,2) ≈ 2,775 pairs exist. Fan-out 20 yields ~1,500 hashes — comfortably available. Fan-out 8 yields ~600. That headroom is the whole argument for Enhancement 2, and it belongs in the paper.

### 3.5 Matching

1. Extract query hashes `Hq [Nq×1]`, anchor times `Tq [Nq×1]`.
2. Look up postings → arrays of `(songID, t1_ref)`, expanded to align with each query hash.
3. Compute `δ = t1_ref − Tq` (integer frames). Shift into a positive range.
4. `counts = accumarray([songID, δ'], 1, [], @sum, 0, true)` — a sparse `nSongs × nOffsets` matrix.
5. Smooth by `±offsetTolFrames` (a 3-wide moving sum along the offset dimension) **for the top-K songs only** — full smoothing of a sparse matrix is wasteful.
6. `score1` = the maximum smoothed bin; `pred1` = its song. `score2` = best of the runner-up song.
7. `normScore = score1 / Nq`; `margin = score1 / max(score2,1)`.
8. **Accept** iff `normScore ≥ tau` **and** `margin ≥ rho`.

> Normalising by `Nq` *is* the proposal's "length-normalized decision threshold." A single `tau` should then work across 3/5/10 s. Verify that empirically; if it does not hold, a per-length `tau` is a legitimate fallback but must be tuned on dev and disclosed.

> Note that `tau` and `rho` must be **re-tuned per system**. Enhanced mode emits more hashes, so `Nq` grows and `normScore` shifts. Reusing the baseline threshold on the enhanced system is the single easiest way to accidentally report a fake result.

### 3.6 Spectral subtraction (Enhancement 1a, query side only)

Estimate the noise magnitude spectrum from the lowest-energy `noiseFrameFrac` of frames, then `|Ŝ| = max(|Y| − α|N̂|, β|Y|)` with the original phase retained. Two things to watch:

- **Asymmetry is intentional but must be validated.** References are clean and are never denoised. Denoising shifts spectral peak locations slightly, so a *clean* query passed through the denoiser may score worse than one that was not. Run a clean-query-through-denoiser regression test at M4 and gate on ≤2 pp loss. If it fails, gate the denoiser on an estimated-SNR test rather than always-on.
- α and β control musical noise. Sweep them on dev only.

### 3.7 Preprocessing symmetry table

Any asymmetry that is not deliberate will silently destroy match rates. Freeze this table and unit-test it.

| Stage | Reference (enrolment) | Query (baseline) | Query (enhanced) |
|---|---|---|---|
| Stereo → mono | ✔ | ✔ | ✔ |
| Resample to 8 kHz (anti-aliased) | ✔ | ✔ | ✔ |
| DC removal | ✔ | ✔ | ✔ |
| RMS normalise to −20 dBFS | ✔ | ✔ | ✔ |
| Pre-emphasis (α = 0.97) | ✔ | ✔ | ✔ |
| Spectral subtraction | ✘ | ✘ | **✔** |
| STFT / peak picking / hashing | ✔ (Cfg-driven) | ✔ | ✔ (adaptive + short-query) |

---

## 4. Repository Structure

Mirrors your existing `DysarthricVCR` layout — same `setupPaths.m` entry point, same `src/` subfolder split, same camelCase function naming — so muscle memory carries over and the two projects look like one coherent body of work.

```
HimigTransform/
├── README.md                       # setup, pinned MATLAB version, how to run each script
├── .gitignore
├── setupPaths.m                    # addpath for src/** ; run once per session
│
├── config/
│   ├── defaultConfig.m             # returns the Cfg struct of §2.1
│   ├── baselineConfig.m            # defaultConfig + baseline overrides
│   ├── enhancedConfig.m            # defaultConfig + enh1 + enh2 overrides
│   └── makeConfigTag.m             # deterministic Cfg -> char tag for filenames
│
├── src/
│   ├── util/
│   │   ├── loadAudio.m             # read -> mono -> resample(fs) -> double
│   │   ├── resampleAudio.m
│   │   ├── rmsNormalize.m
│   │   ├── sha256File.m
│   │   ├── logMsg.m                # single logging entry point (timestamped)
│   │   └── requireToolbox.m        # graceful capability check + fallback dispatch
│   │
│   ├── io/
│   │   ├── ingestLibrary.m         # raw/ -> processed/ 8kHz mono, writes catalog.csv
│   │   ├── buildCatalog.m
│   │   ├── loadCatalog.m
│   │   ├── prepareNoiseBank.m      # DEMAND ch01 16k -> 8k mono, into data/noise/
│   │   ├── saveFingerprint.m
│   │   └── loadFingerprint.m
│   │
│   ├── features/                   # the DSP front end
│   │   ├── preprocessSignal.m      # DC + RMS norm + pre-emphasis
│   │   ├── computeSTFT.m           # framing + window + fft  (NOT named stft.m — see note)
│   │   ├── frameSignal.m
│   │   ├── estimateNoiseSpectrum.m
│   │   └── spectralSubtract.m      # Enhancement 1a
│   │
│   ├── fingerprint/
│   │   ├── pickPeaksFixed.m        # baseline constellation
│   │   ├── pickPeaksAdaptive.m     # Enhancement 1b
│   │   ├── pickPeaks.m             # dispatcher on Cfg.peaks.mode
│   │   ├── enforcePeakDensity.m    # per-second, per-band cap
│   │   ├── makeHashes.m            # anchor/target pairing + fan-out (Enhancement 2)
│   │   ├── packHash.m
│   │   └── unpackHash.m
│   │
│   ├── db/
│   │   ├── enrollDatabase.m        # catalog -> fingerprints -> index (parfor)
│   │   ├── buildIndex.m            # dispatcher: 'csr' | 'map'
│   │   ├── buildIndexCsr.m
│   │   ├── buildIndexMap.m
│   │   ├── queryIndex.m            # uniform lookup across backends
│   │   ├── pruneIndex.m            # drop hashes with > maxPostingsPerHash entries
│   │   └── indexStats.m
│   │
│   ├── match/
│   │   ├── identifyQuery.m         # THE online entry point: audio -> decision struct
│   │   ├── alignOffsets.m          # accumarray histogram + smoothing
│   │   ├── scoreCandidates.m
│   │   └── decideOpenSet.m         # tau + rho rule
│   │
│   ├── eval/
│   │   ├── buildQueryManifest.m    # deterministic excerpt + noise assignment
│   │   ├── synthesizeQuery.m       # manifest row -> waveform (D2)
│   │   ├── mixAtSNR.m              # + measured-SNR return value for verification
│   │   ├── pickExcerptStart.m      # energy-gated (see Risk R10)
│   │   ├── runExperiment.m         # the grid runner
│   │   ├── computeMetrics.m        # accuracy / precision / recall / FAR + Wilson CIs
│   │   ├── mcnemarTest.m           # paired baseline-vs-enhanced significance
│   │   └── tuneThresholds.m        # sweeps tau, rho on DEV only
│   │
│   ├── viz/
│   │   ├── plotAccuracyVsSnr.m
│   │   ├── plotAccuracyVsLength.m
│   │   ├── plotPeakDensityVsSnr.m  # the mechanism figure
│   │   ├── plotOpenSetRoc.m
│   │   ├── plotConstellation.m     # reused by the GUI
│   │   ├── plotOffsetHistogram.m   # reused by the GUI
│   │   └── plotRepertoireConfusion.m
│   │
│   └── gui/
│       ├── HimigTransformApp.mlapp # thin view layer only
│       └── AppController.m         # handle class: all logic, unit-testable
│
├── scripts/                        # numbered, run in order, each idempotent
│   ├── s01_ingest.m
│   ├── s02_prepareNoise.m
│   ├── s03_enroll.m                # builds both indexes
│   ├── s04_buildQueries.m
│   ├── s05_tuneThresholds.m        # DEV split only
│   ├── s06_runEvaluation.m         # TEST split
│   ├── s07_makeFigures.m
│   └── s08_makeTables.m            # LaTeX/Word-ready result tables
│
├── tests/
│   ├── runTests.m                  # runs everything; must be green before any merge
│   ├── tSTFT.m
│   ├── tHashPack.m
│   ├── tMixSNR.m
│   ├── tSelfMatch.m
│   ├── tIndexBackendParity.m
│   └── tPreprocessSymmetry.m
│
├── data/                           # GITIGNORED except the README
│   ├── README.md                   # exactly how to obtain and place the audio
│   ├── raw/{american,opm,holdout}/
│   ├── processed/mono8k/
│   └── noise/                      # PCAFETER_ch01_8k.wav, STRAFFIC_..., SPSQUARE_...
│
├── db/                             # GITIGNORED
│   ├── catalog.csv                 # ← the exception: this one IS committed
│   ├── fingerprints/<cfgTag>/
│   └── index_<cfgTag>.mat
│
├── results/
│   ├── raw/                        # gitignored
│   ├── figures/                    # committed (they go in the paper)
│   └── tables/                     # committed
│
└── docs/
    ├── proposal.pdf
    ├── designNotes.md              # running log of decisions + why
    └── figures/
```

### 4.1 A naming trap worth avoiding

Do **not** create `src/features/stft.m`. It shadows the Signal Processing Toolbox's `stft` for the entire session, which breaks the verification test that is supposed to catch your bugs. Same for `spectrogram.m`, `resample.m`, `hamming.m`. Verb-noun camelCase names (`computeSTFT`, `resampleAudio`) sidestep this entirely and match the convention you already use. If collisions ever get unmanageable, migrate to a `+himig` package namespace — but with disciplined naming you will not need to.

### 4.2 `.gitignore` essentials

```
data/raw/**
data/processed/**
data/noise/**
db/fingerprints/**
db/*.mat
results/raw/**
!db/catalog.csv
!data/README.md
*.asv
```

### 4.3 The `.mlapp` merge problem

`.mlapp` is a binary container. Git cannot merge it, and two members editing it in the same week means one of them loses work. **Assign a single owner for the app file.** Everyone else contributes through `AppController.m` and the `viz/` plotting functions, which are plain text and merge normally. This is exactly why the controller is separated from the view.

---

## 5. Interface Contracts

Freeze these at Milestone 1. Once frozen, the five workstreams in §10 can be developed against stubs in parallel.

```matlab
%% features/
sig      = preprocessSignal(x, fs, Cfg)                    % -> [N x 1] double
[S, f, t]= computeSTFT(sig, Cfg)                           % S: [nBins x nFrames] complex
Nmag     = estimateNoiseSpectrum(Smag, Cfg)                % -> [nBins x 1]
Sclean   = spectralSubtract(S, Nmag, Cfg)                  % complex, phase preserved

%% fingerprint/
peaks    = pickPeaks(Smag, Cfg)                            % struct: .tIdx .fIdx .magDb
peaks    = enforcePeakDensity(peaks, nFrames, Cfg)
[h, t1]  = makeHashes(peaks, Cfg)                          % uint32 [H x 1] each
h        = packHash(f1, f2, dt)                            % vectorised
[f1,f2,dt] = unpackHash(h)                                 % exact inverse

%% db/
fp       = extractFingerprint(sig, Cfg)                    % -> peaks + hashes (one call)
Idx      = buildIndex(fpCellArray, songIDs, Cfg)           % backend chosen by Cfg
post     = queryIndex(Idx, h)                              % -> struct .qIdx .songID .t1
stats    = indexStats(Idx)

%% match/
res      = identifyQuery(sig, Idx, Cfg)
%   res.pred1 .score1 .pred2 .score2 .normScore .margin
%   res.accepted .nQueryHashes .tHashSec .tMatchSec
%   res.offsetHist  (for the GUI figure)   .peaks (for the GUI overlay)

%% eval/
M        = buildQueryManifest(catalog, Cfg)                % -> table
[y, meas]= synthesizeQuery(manifestRow, catalog, Cfg)      % meas.snrDbMeasured
[y, g, snrMeas] = mixAtSNR(x, n, targetSnrDb)
R        = runExperiment(M, Idx, Cfg, systemName)          % -> long-format table
T        = computeMetrics(R, groupVars)                    % + Wilson CIs
[tau,rho]= tuneThresholds(Rdev, Cfg)
```

**Test contracts** (`tests/runTests.m` must be green before every merge):

| Test | Asserts |
|---|---|
| `tSTFT` | `computeSTFT` matches `spectrogram()` on the same window/hop/nfft to < 1e-10 relative error |
| `tHashPack` | `unpackHash(packHash(f1,f2,dt))` is exact over the full valid range, including edges |
| `tMixSNR` | `mixAtSNR` returns a measured SNR within 0.1 dB of target across [Inf 20 10 5 0 −5] |
| `tSelfMatch` | A clean 10 s excerpt of an enrolled song returns that song with `margin > 3` |
| `tIndexBackendParity` | `csr` and `map` backends return identical postings for the same query hashes |
| `tPreprocessSymmetry` | Reference and query paths produce identical peak sets on identical clean input |

---

## 6. Design Notes on the Sharp Edges

### 6.1 RMS normalisation, not peak normalisation
Peak normalisation makes a heavily-compressed modern master and a dynamic 1970s recording sit at wildly different loudness, so the same fixed peak-picking threshold behaves differently on each — and your SNR mixing becomes meaningless because "signal power" varies by 15 dB across the catalog. Normalise to a fixed RMS (−20 dBFS), then check for clipping.

### 6.2 SNR mixing, done correctly
```
Px = mean(x.^2);  Pn = mean(n.^2);
g  = sqrt(Px / (Pn * 10^(snrDb/10)));
y  = x + g*n;
if max(abs(y)) > 0.99, y = y * 0.99/max(abs(y)); end   % rescaling does not change SNR
```
Mix **after** both signals are at 8 kHz, so the SNR you report is the in-band SNR the system actually experiences. Compute power over the excerpt, never the whole song. Return the measured SNR and assert it in `tMixSNR`.

### 6.3 Timing measurement
`tic/toc` on a cold call measures MATLAB's JIT, not your algorithm. Discard the first 5 calls, report the **median and 95th percentile** over ≥100 calls, exclude index loading (that is a one-time startup cost, reported separately), and note the machine spec in the paper. Success criterion #3 says "under one second" — you will likely be an order of magnitude under it with the CSR backend, which is worth stating.

### 6.4 Reproducibility discipline
`rng(Cfg.seed,'twister')` at the top of every script. Every results file embeds `Cfg`, the config tag, the MATLAB version, and the Git commit hash (`system('git rev-parse --short HEAD')`). When a reviewer asks "which settings produced Figure 4," the answer is in the file.

### 6.5 Posting-list pruning
Some hashes are near-universal (a common `(f1,f2,Δt)` combination appearing in dozens of songs). They contribute nothing to discrimination and dominate lookup cost. Drop any hash whose posting list exceeds `maxPostingsPerHash`, log how many were dropped, and report the effect on accuracy and match time. This is textbook IR stop-word pruning applied to fingerprints — cheap to implement, and a nice half-paragraph in the results.

---

## 7. Implementation Milestones

Each milestone has an **exit test**. Do not start the next one until it passes. Weeks are relative — anchor them to your actual term calendar.

### M0 — Skeleton and data spine *(Week 1)*
Repo, `setupPaths.m`, `defaultConfig.m`, `.gitignore`, `README.md` with the pinned MATLAB version. Implement `loadAudio`, `resampleAudio`, `rmsNormalize`, `ingestLibrary`, `prepareNoiseBank`. Ingest a **5-song toy set** plus the three DEMAND files.
**Exit:** `runTests.m` runs (even with mostly-empty tests); `catalog.csv` exists with checksums; every processed file is verified 8 kHz mono.

### M1 — Vertical slice *(Week 2)* ← **freeze the interfaces here**
The thinnest possible end-to-end path: preprocess → `computeSTFT` → `pickPeaksFixed` → `makeHashes` → `buildIndexCsr` → `identifyQuery`, on the 5-song toy set, clean audio only, no GUI, no evaluation.
**Exit:** `tSTFT` and `tHashPack` pass; `tSelfMatch` passes on all 5 toy songs at 10 s clean with `margin > 3`. Publish the §5 signatures to the group and stop changing them.

### M2 — Baseline at full scale *(Week 3)*
Ingest all 120 songs. `enrollDatabase` with `parfor`. Implement `buildIndexMap` and `tIndexBackendParity`. Benchmark both backends and record the numbers — they go in the paper.
**Exit:** 100 songs enrolled; ≥95% top-1 on clean 10 s queries; enrolment under 15 minutes; median match time under 1 s. Record `indexStats` for both backends.

### M3 — Evaluation harness *(Week 4)* ← **the milestone people skip and regret**
`buildQueryManifest`, `synthesizeQuery`, `mixAtSNR`, `pickExcerptStart`, `runExperiment`, `computeMetrics`, and the first two plots. Run the **full grid on the baseline** over a 20-song subset to validate the pipeline end-to-end, then over all 100.
**Exit:** `tMixSNR` passes; a complete baseline results table exists; `plotAccuracyVsSnr` and `plotAccuracyVsLength` generate from it unattended.
**Then: `git tag v0.1-baseline-frozen`.** Every later comparison points at this tag.

### M4 — Enhancement 1: denoising + adaptive peaks *(Weeks 5–6)*
`estimateNoiseSpectrum`, `spectralSubtract`, `pickPeaksAdaptive`. Sweep α, β, and `kappaDb` **on the dev split only**. Produce `plotPeakDensityVsSnr` — the mechanism figure. Run the `freqDecim` ablation here too.
**Exit:** ≥10 pp gain over baseline at 0 dB on **dev**; ≤2 pp regression on clean 10 s (the clean-query-through-denoiser gate from §3.6). Ablate the two sub-components separately — denoiser alone vs adaptive peaks alone vs both — so the paper can attribute the gain.

### M5 — Enhancement 2: short-query mode + open-set *(Week 7)*
Query-length-conditional fan-out and `dtMax`; build `index_enhanced`. `decideOpenSet`, `tuneThresholds`, `plotOpenSetRoc`. Choose the operating point on dev and **write it into `enhancedConfig.m` before touching the test split.**
**Exit:** measurable gain at 3 s; ROC over the 20 holdout songs; `tau` and `rho` frozen in config with the dev-tuning evidence archived.

### M6 — GUI *(Week 8, parallelisable with M5)*
`AppController.m` first, `.mlapp` second. Index loaded once in `StartupFcn` behind a `uiprogressdlg`. Panels: load/record/play; waveform; spectrogram with constellation overlay; offset histogram; ranked results table; baseline↔enhanced toggle; match time; accept/reject badge.
**Exit:** cold start to first identification under 30 s on the demo laptop; both modes switchable without restart; a pre-recorded WAV fallback exists in case the venue microphone fails.

### M7 — Full factorial run, figures, paper *(Weeks 9–10)*
`s06_runEvaluation.m` over the complete grid on the **test** split, both systems. All figures and LaTeX/Word tables generated by script — no hand-made plots. McNemar tests and Wilson CIs on every headline claim. Repertoire confusion analysis for the American-vs-OPM transfer claim.
**Exit:** every number in the paper traces to a committed script and a results file.

### M8 — Hardening and freeze *(Week 11)*
Fresh-clone rehearsal on a machine that has never seen the project: clone, follow `README.md`, run `s01`…`s07`, confirm the figures reproduce. Dry-run the demo twice. Tag `v1.0-final`.

---

## 8. Evaluation Protocol

### 8.1 The grid
Clean has no noise type, so the conditions are `1 (clean) + 3 SNR × 3 noise types = 10` per query length.

```
3 lengths × 10 conditions × 120 songs × 3 reps = 10,800 queries per system
```
At ~0.2–0.5 s per match that is roughly 1–3 hours per system with `parfor`. Budget a full day for M7 and run it twice.

### 8.2 Splits — the leakage rule
Split **at the song level**, not the query level: 20% of songs (and 10 of the 20 holdout songs) → `dev`; the rest → `test`. All sweeps of α, β, `kappaDb`, `tau`, `rho`, `freqDecim` happen on dev. **The test split is touched exactly once, at M7.** Tuning a threshold on the data you report is the most common way a project like this produces a number it cannot defend at the panel.

### 8.3 Metric definitions
Your objectives name precision and recall, which are only meaningful once rejection exists. Define them explicitly in the paper:

- **Closed-set top-1 accuracy** — over in-DB queries, `pred1 == songID`, ignoring the threshold. Measures the matcher.
- **Identification accuracy (operational)** — `correct AND accepted`. Measures the system.
- **Precision** = correct-and-accepted / all-accepted *(the denominator includes wrongly-accepted holdout queries)*.
- **Recall** = correct-and-accepted / all in-DB queries.
- **FAR** = accepted holdout queries / all holdout queries.
- **Match time** — median and p95 of the online path, index load excluded.

Report all of these split by repertoire (`american` / `opm`) — that split *is* the paper's novelty claim.

### 8.4 Statistics
- **Wilson score 95% CI** on every reported accuracy. At n = 150 per cell and p ≈ 0.85 the half-width is roughly ±5.7 pp — which means a claimed 10-pp gain needs the paired test below, not overlapping error bars, to be defensible.
- **McNemar's exact test** on baseline vs enhanced. The paired manifest design (§2.5) is what makes this valid: the same excerpt, the same noise segment, the same SNR, two systems.
- Report `n` in every table. If the 10-pp claim lands marginal, raise `repsPerSong` from 3 to 5 — that is a re-run, not a redesign.

---

## 9. Risk Register

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | `containers.Map` build blows up memory or time | Enrolment unusable | CSR backend behind the same interface (D3); report the benchmark as a finding |
| R2 | Audio sourcing for 120 songs stalls | Blocks M2 onward | Assign at M0; `data/README.md` + checksums; raw audio never committed or redistributed |
| R3 | Denoising *hurts* clean and high-SNR queries | Enhancement looks like a regression | Clean-query gate at M4; fall back to SNR-conditional denoising |
| R4 | 0 dB + 3 s is unrecoverable for both systems | Success criterion #1 unmet | Add a 15 dB and 20 dB point so the curve shows a knee; report the honest floor and where the gain does exist; ablate to show the mechanism works even where the absolute number is low |
| R5 | Thresholds tuned on the reported data | Result indefensible at the panel | Song-level dev/test split (§8.2); thresholds committed to config before M7 |
| R6 | Peak density varies wildly across masters | Loud tracks dominate the index | Per-second, per-band density cap (§3.3); plot peaks/s per song as a QA check |
| R7 | Two people edit `.mlapp` in the same week | Lost work | Single app owner; everyone else works in `AppController.m` |
| R8 | MATLAB version / toolbox mismatch across members | Late integration failure | Pin the version in `README.md`; `requireToolbox.m` with fallbacks; fresh-clone rehearsal at M8 |
| R9 | Timing numbers are noisy or JIT-contaminated | Criterion #3 not credible | Warm-up discard, median + p95 over ≥100 runs, machine spec recorded |
| R10 | Excerpts land on intros, fades, or silence | Failures unrelated to the algorithm | Energy-gate `pickExcerptStart`: reject any candidate window below a fraction of the track's median frame energy; log rejection rate |
| R11 | Demo laptop microphone/permissions fail live | Objective #4 fails at the worst moment | Pre-recorded WAV fallback set; rehearse on the actual machine at M8 |

---

## 10. Group Work Split

Interfaces freeze at M1, after which these five streams run in parallel against stubs.

| Stream | Owns | Milestone weight |
|---|---|---|
| **A — Data & I/O** | `io/`, `util/`, catalog, DEMAND noise bank, `data/README.md`, checksums | M0, M2 |
| **B — DSP front end** | `features/`, `pickPeaks*`, `enforcePeakDensity`, spectral subtraction | M1, M4 |
| **C — Fingerprint & index** | `fingerprint/`, `db/`, both backends, pruning, benchmarks | M1, M2, M5 |
| **D — Matching & evaluation** | `match/`, `eval/`, `viz/`, statistics, threshold tuning | M3, M5, M7 |
| **E — GUI & integration** | `gui/`, `scripts/`, `tests/runTests.m`, paper figure assembly | M6, M7, M8 |

Everyone writes tests for their own module. `runTests.m` green is the merge gate.

---

## 11. Traceability — proposal commitments → artifacts

| Commitment | Milestone | Artifact that proves it |
|---|---|---|
| Obj. 1 — 100-song DB, baseline pipeline | M2 | `catalog.csv`, `index_<baselineTag>.mat`, `indexStats` output |
| Obj. 2 — Enhancements 1 and 2 | M4, M5 | `enhancedConfig.m` + the component-wise ablation table |
| Obj. 3 — accuracy/precision/recall/time across SNR × length × repertoire | M7 | `results/tables/*`, `plotAccuracyVsSnr`, `plotAccuracyVsLength` |
| Obj. 4 — App Designer GUI | M6 | `HimigTransformApp.mlapp` + demo rehearsal notes |
| Crit. 1 — ≥10 pp gain at 0 dB | M4 (dev), M7 (test) | McNemar test + Wilson CIs |
| Crit. 2 — ≥85% at 5 s clean | M2 (indicative), M7 (final) | Results table, clean row |
| Crit. 3 — mean match time < 1 s | M2, M7 | Timing table, median + p95, machine spec |
| Crit. 4 — functional GUI | M6, M8 | Live demo + fallback WAV set |
| Novel claim — first American/OPM fingerprinting benchmark | M7 | Per-repertoire results + `plotRepertoireConfusion` |

---

## 12. Three things I would push back on in the proposal

Raise these with your adviser early rather than discovering them in week 9.

1. **`containers.Map` is written into the methodology as if it were a design requirement.** It is an implementation detail with a real scalability cost at 100 songs. Frame the CSR index as a documented engineering improvement with a benchmark table — that reads as rigour, not as deviation.

2. **The SNR grid has no knee.** `[clean, 10, 5, 0]` jumps straight from clean (∞) to 10 dB. Adding 20 dB and 15 dB costs almost nothing (the harness already loops) and gives you a curve with visible structure instead of two points and a cliff. It also protects you if 0 dB turns out to be a floor for both systems (R4).

3. **Precision and recall are listed as metrics but the proposal defines no rejection rule outside the open-set paragraph.** Without a threshold, precision equals recall equals accuracy and the metrics are vacuous. Section 8.3 fixes this — make sure the same definitions appear in the final paper, or the panel will ask.
