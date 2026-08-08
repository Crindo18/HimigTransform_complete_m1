function M = buildQueryManifest(catalog, Cfg)
%BUILDQUERYMANIFEST Generate the deterministic query manifest table.
%
%   The manifest IS the query set (blueprint D2) - no query WAVs are
%   written.
%   Columns are listed in blueprint 2.5.
%
%   INVARIANT: the same (songID, lengthSec, rep, startSample) tuple appears
%   once per noise condition. That paired design is what licenses McNemar's
%   test on the baseline-vs-enhanced comparison.
%
%   Milestone: M3.  Blueprint: section(s) 0 (D2), 2.5.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also SYNTHESIZEQUERY, PICKEXCERPTSTART, MCNEMARTEST.

error('HimigTransform:NotImplemented', ...
    'buildQueryManifest is a stub (Milestone M3). See docs/designNotes.md.');

end
