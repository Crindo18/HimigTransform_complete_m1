%S02_PREPARENOISE  Build the 8 kHz noise bank from the DEMAND recordings.
%
%   Expects the 16 kHz DEMAND release. Takes channel 01 of PCAFETER,
%   STRAFFIC and SPSQUARE and resamples to 8 kHz into data/noise/.
%
%   DEMAND is CC BY-SA 3.0 - attribute it in the paper.
%
%   Milestone: M0.  Blueprint: section 7.
%
%   STATUS: stub. Run order is s01 -> s08; each script is idempotent.
%
%   Usage:
%       setupPaths;
%       s02_prepareNoise

setupPaths;
rng(defaultConfig().seed, 'twister');

error('HimigTransform:NotImplemented', ...
    's02_prepareNoise is a stub (Milestone M0). See docs/designNotes.md.');
