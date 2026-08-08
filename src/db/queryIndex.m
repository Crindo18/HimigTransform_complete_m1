function post = queryIndex(Idx, h)
%QUERYINDEX Look up query hashes and return the matching postings.
%
%   Returns post.qIdx (which query hash each posting came from), post.songID
%   and post.t1. Both backends MUST return identical postings for the same
%   input - tIndexBackendParity enforces this.
%
%   Milestone: M2.  Blueprint: section(s) 2.4, 3.5.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also BUILDINDEX, ALIGNOFFSETS.

error('HimigTransform:NotImplemented', ...
    'queryIndex is a stub (Milestone M2). See docs/designNotes.md.');

end
