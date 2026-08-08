function Idx = buildIndex(fpCellArray, songIDs, Cfg)
%BUILDINDEX Build the hash index. Dispatches on Cfg.index.backend.
%
%   Thin interface over two interchangeable backends so the storage decision
%   is reversible and measurable (blueprint D3).
%
%   Milestone: M2.  Blueprint: section(s) 0 (D3), 2.4.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also BUILDINDEXCSR, BUILDINDEXMAP, QUERYINDEX.

error('HimigTransform:NotImplemented', ...
    'buildIndex is a stub (Milestone M2). See docs/designNotes.md.');

end
