function Idx = buildIndexCsr(fpCellArray, songIDs, Cfg)
%BUILDINDEXCSR Sorted CSR-style index: hashKeys + bucketPtr + postings. Default backend.
%
%   Concatenate all (hash, songID, t1) triples, sortrows by hash, then
%   derive
%   hashKeys (sorted unique) and bucketPtr (CSR offsets). Lookup becomes a
%   binary search plus a vectorised range expansion.
%
%   Budget at 100 songs: baseline ~4.2 M postings, ~45 MB; enhanced ~10.5 M
%   postings, ~110 MB.
%
%   Milestone: M2.  Blueprint: section(s) 2.4.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also BUILDINDEX, QUERYINDEX, PRUNEINDEX.

error('HimigTransform:NotImplemented', ...
    'buildIndexCsr is a stub (Milestone M2). See docs/designNotes.md.');

end
