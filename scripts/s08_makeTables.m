%S08_MAKETABLES  Regenerate the result tables, with Wilson CIs and McNemar p-values.
%
%   Reports n in every cell. The 10 pp claim is carried by the paired
%   McNemar
%   test, not by non-overlapping error bars.
%
%   Milestone: M7.  Blueprint: section 7.
%
%   STATUS: stub. Run order is s01 -> s08; each script is idempotent.
%
%   Usage:
%       setupPaths;
%       s08_makeTables

setupPaths;
rng(defaultConfig().seed, 'twister');

error('HimigTransform:NotImplemented', ...
    's08_makeTables is a stub (Milestone M7). See docs/designNotes.md.');
