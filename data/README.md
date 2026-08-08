# `data/` — how to populate it

Nothing in this folder is committed. The repository carries only
`db/catalog.csv` (with SHA-256 checksums) so that every group member can
verify they are holding byte-identical audio.

## 1. Music — 120 tracks

```
data/raw/american/    50 tracks, several decades and genres
data/raw/opm/         50 tracks, ballad / pop-rock / Taglish-pop
data/raw/holdout/     20 tracks, NOT enrolled — these test open-set rejection
```

Any format `audioread` can open. `s01_ingest` converts everything to 8 kHz
mono WAV in `data/processed/mono8k/`.

**Handling.** Use tracks the group already owns. Raw audio is gitignored and
must not be redistributed; state the academic-use basis in the paper's dataset
section. `catalog.csv` carries checksums, not audio, so it is safe to commit.

**Holdout selection matters.** Pick the 20 holdout tracks to be *plausible*
confusions — same artists, same genres, same era as the enrolled set. Twenty
obviously different tracks make open-set rejection look easy and the FAR
number becomes meaningless.

## 2. Noise — DEMAND

Download from Zenodo (record 1227121), 16 kHz release, and take **channel 01**
of these three:

| DEMAND | `noiseType` | Recording |
|---|---|---|
| `PCAFETER` | `cafe` | Busy office cafeteria |
| `STRAFFIC` | `traffic` | Busy traffic intersection |
| `SPSQUARE` | `crowd` | Public town square with tourists |

`s02_prepareNoise` resamples them to 8 kHz into `data/noise/`. Each recording
is 300 s, which is ample: query noise segments are drawn from random seeded
offsets within it.

DEMAND is **CC BY-SA 3.0** — attribute it in the paper. ShareAlike applies to
derivatives you redistribute, so do not publish mixed audio.

## 3. Verify

```matlab
setupPaths;
s01_ingest;
s02_prepareNoise;
```

Every processed file must be 8 kHz mono, and `catalog.csv` must have 120 rows
with unique `songID` values and a populated `sha256` column.
