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

## Pending decisions

These are open and should be resolved at the milestone named.

| Question | Resolve at | Notes |
|---|---|---|
| `freqDecim` = 1 or 2? | M4 | 15.6 Hz vs ~31 Hz hash resolution. Ablate, don't guess. |
| `medfilt2` (exact 2-D) vs `movmedian` (separable) for the adaptive threshold | M4 | Benchmark once; `movmedian` avoids the Image Processing Toolbox dependency |
| Extend the SNR grid to `[Inf 20 15 10 5 0]`? | before M3 | Costs nothing, gives the curve a knee. Ask the adviser. |
| Single `tau` across query lengths, or per-length? | M5 | Normalising by `nQueryHashes` should make one `tau` work. Verify. |
| `repsPerSong` 3 or 5? | M7 | Raise to 5 if the 10 pp claim lands marginal. |
