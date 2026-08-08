%S06_RUNEVALUATION  Run the full factorial on the TEST split, both systems.
%
%   3 lengths x 10 conditions x 120 songs x 3 reps = about 10,800 queries
%   per
%   system; roughly 1-3 h each with parfor. Budget a full day and run twice.
%
%   Every results file embeds Cfg, Cfg.tag, the MATLAB version and the git
%   commit hash so any number in the paper traces back to what produced it.
%
%   Milestone: M7.  Blueprint: section 7.
%
%   STATUS: stub. Run order is s01 -> s08; each script is idempotent.
%
%   Usage:
%       setupPaths;
%       s06_runEvaluation

setupPaths;
rng(defaultConfig().seed, 'twister');

error('HimigTransform:NotImplemented', ...
    's06_runEvaluation is a stub (Milestone M7). See docs/designNotes.md.');
