function Idx = buildIndexMap(fpCellArray, songIDs, Cfg)
%BUILDINDEXMAP containers.Map index - the proposal-faithful backend.
%
%   BUILD IT IN ONE SHOT. Assemble the flat triple array, sortrows by hash,
%   split into a cell array on run lengths with mat2cell, then call the
%   containers.Map(keys, values) constructor ONCE.
%
%   Never do M(key) = [M(key); newRow] in a loop - that pattern is O(n^2)
%   and
%   will not finish in reasonable time at this scale. Expect this backend to
%   cost several hundred MB more than CSR; measure it, because the
%   comparison
%   is a reportable finding rather than a deviation to hide.
%
%   Milestone: M2.  Blueprint: section(s) 0 (D3), 2.4.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also BUILDINDEX, BUILDINDEXCSR.

error('HimigTransform:NotImplemented', ...
    'buildIndexMap is a stub (Milestone M2). See docs/designNotes.md.');

end
