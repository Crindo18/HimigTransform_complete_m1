%S05_TUNETHRESHOLDS  Sweep tau and rho on the DEV split.
%
%   DEV ONLY. The test split is touched exactly once, at s06 (M7).
%
%   Write the chosen tau and rho back into config/enhancedConfig.m and
%   commit
%   that change BEFORE running s06. If the thresholds move after you have
%   seen
%   test results, the result is no longer defensible.
%
%   Milestone: M5.  Blueprint: section 7.
%
%   STATUS: stub. Run order is s01 -> s08; each script is idempotent.
%
%   Usage:
%       setupPaths;
%       s05_tuneThresholds

setupPaths;
rng(defaultConfig().seed, 'twister');

error('HimigTransform:NotImplemented', ...
    's05_tuneThresholds is a stub (Milestone M5). See docs/designNotes.md.');
