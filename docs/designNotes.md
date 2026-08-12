# Design Notes

A running log of decisions and why they were made. When a future group member
(or you in week 10) asks "why is it like this?", the answer goes here rather
than in a Slack thread nobody can find.

Format: one dated entry per decision. Record the decision, the alternative
that was rejected, and what would make you revisit it.

---

## D1–D4 — carried over from the blueprint

See `HimigTransform_Blueprint.md` §0. Summarised:

1. **Evaluation harness before enhancements** (M3 before M4). You cannot claim
   a gain you did not measure against a frozen reference.
2. **No query WAVs.** The manifest plus a fixed seed reproduces every waveform.
3. **Two index backends** behind one interface. `csr` by default,
   `containers.Map` for proposal fidelity, benchmarked against each other.
4. **One index per configuration.** No shared superset index.

---

## 2026-08-09 — `Cfg.hash.queryFanout` / `queryDtMax` added

**Decision.** The blueprint's §2.1 had a single `Cfg.hash.fanout`, but that
field has to serve three roles: enrolment, default query, and short-query
override. In the enhanced configuration the database needs `fanout = 20`,
`dtMax = 64` so short-query hashes have something to collide with — but long
queries should stay at the baseline fan-out so Enhancement 2 can be ablated
independently of the wider database.

Added `Cfg.hash.queryFanout` and `Cfg.hash.queryDtMax`, both `[]` meaning
"inherit the enrolment value", plus `config/resolveQueryConfig.m` to apply the
three-tier resolution in one place.

**Rejected alternative.** Threading a `role` argument through `makeHashes`.
That would have changed the §5 interface contract, which is meant to be frozen
at M1, and it would have put configuration logic inside a DSP function.

**Revisit if.** The ablation shows long-query fan-out has no measurable effect,
in which case the extra fields are dead weight and can collapse back to one.

**Guard added.** `resolveQueryConfig` warns and clamps when the query target
zone exceeds the enrolment zone. Without it, the symptom is "nothing matches",
which looks like an algorithm bug and is very hard to trace to a config
mismatch.

---

## 2026-08-09 — `setupPaths` returns the project root

**Decision.** Dropped the planned `projectRoot.m` helper. `setupPaths` already
knows the root via `mfilename('fullpath')` and every script calls it anyway, so
a second function would have been one more thing to keep in sync.

---

## 2026-08-12 — M2 review: what was actually complete, and what was not

The M1 and M2 work landed but neither was committed — 46 modified files sat
uncommitted on top of the M0 commit. Reconstructed and committed as two
milestones so `v0.1-baseline-frozen` at M3 has something to point at.

Three things were outstanding against the blueprint's M2 gate, all now closed:

| | Blueprint | State found | Action |
|---|---|---|---|
| `buildIndexMap` | M2 | stub | implemented |
| `pruneIndex` | M2 | stub | implemented |
| `tIndexBackendParity` | M2 | 3 tests, all `assumeFail` | 8 live tests |

The backend comparison is not optional polish: it is the reportable finding
that justifies substituting a CSR index for the `containers.Map` the proposal
names in its methodology (blueprint D3). Without it the substitution is an
undocumented deviation.

---

## 2026-08-12 — Shape bug in `queryIndex` (found by the missing test)

`repelem` returns a ROW when its first argument is 1x1, because a 1x1 array is
simultaneously a row and a column vector. In the posting expansion

```matlab
offs = (1:total)' - repelem(runStart, lens);
```

that made the subtraction broadcast into a `total x total` matrix, so every
returned field came back square. Confirmed: a lookup of one hash against a
3-posting bucket returned `songID` sized `[3 3]` and `qIdx` sized `[1 3]`.

**Why it never showed.** A real 10 s query retrieves thousands of postings
across hundreds of keys, so every intermediate is a genuine column and the
arithmetic is correct. The failure needs exactly one query hash matching
exactly one bucket — which is what a unit test does, and what an integration
run never does. The 100-song enrolment at M2 passed with 100% clean top-1
accuracy while this bug was live.

**Fixed** by forcing every intermediate to a column. `pruneIndex` uses the
same expansion and carries the same guard.

`tIndexBackendParity/testSingleHashLookupReturnsAColumn` is the regression
test. It asserts SHAPE, not just contents — contents alone pass, because the
first column of the square result happens to be right.

This is the second instance of this exact bug in the project. Treat
`repelem` in any expansion as requiring a `(:)` or `reshape(..., [], 1)`.

---

## 2026-08-12 — The density cap is inert (DECIDE BEFORE M3 FREEZES)

`Cfg.peaks.densityPerSec = 25` currently has no effect. Two mechanisms limit
constellation density and only one is a parameter:

1. **Geometry.** A peak must be maximal over an `nbhdF x nbhdT`
   neighbourhood, so the most a spectrogram can hold is
   `(frameRate/nbhdT) * (nBins/nbhdF)` = **18.2 peaks/s** at 21x21.
2. **The cap.** `enforcePeakDensity` keeps the top `K = round(25/5) = 5` per
   (second, band).

The target sits above the ceiling, so the cap can never bind. Measured density
on the 100-song corpus was **12.1/s** — set entirely by the neighbourhood.
Per band it is worse: bands 1-4 have geometric ceilings of 1.1, 1.1, 2.3 and
4.5 peaks/s against a budget of 5, so only the top band can ever fill its
allocation.

**Why this is not cosmetic.** Blueprint 3.3 caps per second and per band for
two reasons: so a six-minute track cannot dominate the index over a
two-minute one, and so the bass region cannot swallow the budget. Neither
guarantee holds while the cap is inert. More seriously, at M4 both peak
pickers run through `enforcePeakDensity` precisely so fixed and adaptive are
compared at **equal peak budget** — if the cap never binds, the adaptive
picker can win by emitting more peaks, which is the exact confound the design
exists to remove.

It also explains the index-size gap: 1.44 M postings measured against the
blueprint's 4.2 M estimate, which assumed 25 peaks/s.

**Three options.** All change the baseline, so choose before `git tag
v0.1-baseline-frozen`:

| | Change | Effect | Cost |
|---|---|---|---|
| A | `nbhd` 21x21 -> 13x13 | ceiling 47.5/s, cap binds, density ~25/s | smaller neighbourhoods admit weaker, closely spaced maxima — the first thing noise destroys, which is the robustness the project exists to measure |
| B | `densityPerSec` 25 -> 12 | parameter becomes honest, nothing else moves | the cap still does not select; it just stops claiming to |
| C | per-band budget proportional to band width | low bands stop being ceiling-limited | changes the band balance the design deliberately imposes |

**Recommendation: measure, do not guess.** Sweep `nbhd` over {21, 17, 15, 13}
on the real corpus and record achieved density, clean 10 s top-1 accuracy, and
index size. Pick on the numbers, then freeze. This is a half-hour run — 100
songs enrol in 14 s — and it is the last cheap moment to make the choice.

`peakBudgetAudit(Cfg, true)` prints the whole analysis and now runs inside
`s03_enroll`. `tPeakBudget` pins the current state so that a change to the
neighbourhood, the target, the band edges or the STFT grid fails the suite
and forces the decision to be deliberate.

---

## 2026-08-12 — Pruning is measured but NOT applied

`s03_enroll` reports what `pruneIndex` would remove and leaves the index
alone. At `maxPostingsPerHash = 500` against a measured maximum posting list
of 261, it removes nothing.

Pruning changes what the index can match, so it does not enter a baseline
that M3 is about to freeze on the strength of a plausible-sounding default.
Blueprint 6.5 asks for the effect on accuracy **and** match time; a threshold
aggressive enough to save real time can also remove hashes a short noisy
query needed, and the two have to be quoted together.

Verified on the toy corpus: at a threshold of 2, both backends drop the same
1,087 keys and 7,264 postings, surviving buckets keep their exact contents,
the operation is idempotent, and all five songs still identify.

---

## 2026-08-12 — The `containers.Map` cost, measured

First numbers from the toy corpus (5 songs, 12,356 postings, 5,510 keys):

| | csr | containers.Map |
|---|---|---|
| build | 0.00 s | 0.08 s |
| prune | 0.00 s | 5.20 s |
| estimated size | 0.1 MB | 0.6 MB |

The pruning gap is the honest one to quote: `containers.Map` has no vectorised
multi-key operation, so removing 1,087 keys is 1,087 separate `remove` calls.
At 100 songs and 548,273 keys that scales badly, and it is exactly the cost
blueprint D3 predicted.

`s03_enroll` now produces the same table on the real database, with `whos`
for measured memory rather than the estimate. Set `HIMIG_SKIP_MAP=1` to skip
it once the numbers are recorded.

**Do not "optimise" the map lookup loop.** The per-key dispatch cost IS the
finding. Making it fast in a way the CSR backend would not also get would
flatter the comparison and undermine the paper's claim.

---

## 2026-08-12 — `identifyQuery` now returns a real `accepted`

M1 returned `NaN` deliberately, so nobody could read a decision off an
uncalibrated threshold. `decideOpenSet` is now implemented and wired in, and
`accepted` is a logical computed from `tau = 0.02`, `rho = 1.50`.

**Those are placeholders, not calibrated values.** They are tuned on the dev
split at M5. Until then, `accepted` is a plumbing check, not a result — do not
quote a false-accept rate from it. `tSelfMatch` logs the separation on the toy
set as a reminder of what the tuning has to work with.

---

## Pending decisions

These are open. Resolve at the milestone named.

| Question | Resolve at | Notes |
|---|---|---|
| **Peak neighbourhood: 21x21 or smaller?** | **before M3 freeze** | The density cap is inert at 21x21. Sweep {21, 17, 15, 13} on the real corpus and pick on measured accuracy and density. |
| SNR grid: `[Inf 10 5 0]` or `[Inf 20 15 10 5 0]`? | before M3 | Currently the proposal's four points. The extended grid locates the knee of the accuracy curve and hedges risk R4; it is strictly additive (the four headline points are unchanged) and costs a 1.6x longer M7 run. |
| Turn pruning on? | M3 | Inert at the default. Needs an accuracy AND match-time measurement first. |
| `freqDecim` = 1 or 2? | M4 | 15.6 Hz vs ~31 Hz hash resolution. Ablate, don't guess. |
| Redistribute unused per-band peak budget? | M3 | Would raise density; risks bass domination. Tied to the neighbourhood decision. |
| Gate `margin` behind a minimum absolute score? | M5 | Margin is a ratio of small counts and is noisy for out-of-database queries. |

These are open and should be resolved at the milestone named.

| Question | Resolve at | Notes |
|---|---|---|
| `freqDecim` = 1 or 2? | M4 | 15.6 Hz vs ~31 Hz hash resolution. Ablate, don't guess. |
| `medfilt2` (exact 2-D) vs `movmedian` (separable) for the adaptive threshold | M4 | Benchmark once; `movmedian` avoids the Image Processing Toolbox dependency |
| Extend the SNR grid to `[Inf 20 15 10 5 0]`? | before M3 | Costs nothing, gives the curve a knee. Ask the adviser. |
| Single `tau` across query lengths, or per-length? | M5 | Normalising by `nQueryHashes` should make one `tau` work. Verify. |
| `repsPerSong` 3 or 5? | M7 | Raise to 5 if the 10 pp claim lands marginal. |
