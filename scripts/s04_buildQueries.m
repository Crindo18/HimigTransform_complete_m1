%S04_BUILDQUERIES  Generate the deterministic query manifest.
%
%   Writes results/queryManifest.csv. No query WAVs (blueprint D2) - the
%   manifest plus a fixed seed reproduces every waveform on demand.
%
%   Exports about 30 real WAVs for the GUI demo and the paper figures only.
%
%   Milestone: M3.  Blueprint: section 7.
%
%   STATUS: stub. Run order is s01 -> s08; each script is idempotent.
%
%   Usage:
%       setupPaths;
%       s04_buildQueries

setupPaths;
rng(defaultConfig().seed, 'twister');

error('HimigTransform:NotImplemented', ...
    's04_buildQueries is a stub (Milestone M3). See docs/designNotes.md.');
