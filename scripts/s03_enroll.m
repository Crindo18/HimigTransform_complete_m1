%S03_ENROLL  Fingerprint the 100 in-database songs and build BOTH indexes.
%
%   Builds index_<baselineTag>.mat and index_<enhancedTag>.mat from the same
%   extraction run. Two indexes, not one shared superset (blueprint D4) -
%   a wider database zone changes baseline behaviour and contaminates the
%   comparison.
%
%   Also records indexStats for the csr and map backends: that comparison
%   table goes in the paper.
%
%   Milestone: M2.  Blueprint: section 7.
%
%   STATUS: stub. Run order is s01 -> s08; each script is idempotent.
%
%   Usage:
%       setupPaths;
%       s03_enroll

setupPaths;
rng(defaultConfig().seed, 'twister');

error('HimigTransform:NotImplemented', ...
    's03_enroll is a stub (Milestone M2). See docs/designNotes.md.');
