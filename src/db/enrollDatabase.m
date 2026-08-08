function Idx = enrollDatabase(catalog, Cfg)
%ENROLLDATABASE Fingerprint every in-database song and build the index.
%
%   parfor over songs (degrades to serial without Parallel Computing
%   Toolbox).
%   Writes the per-song fingerprint cache, then calls BUILDINDEX once.
%   Target: 100 songs enrolled in under 15 minutes (M2 exit criterion).
%
%   Milestone: M2.  Blueprint: section(s) 7 (M2).
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also EXTRACTFINGERPRINT, BUILDINDEX.

error('HimigTransform:NotImplemented', ...
    'enrollDatabase is a stub (Milestone M2). See docs/designNotes.md.');

end
