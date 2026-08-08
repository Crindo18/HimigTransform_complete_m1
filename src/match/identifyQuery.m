function res = identifyQuery(sig, Idx, Cfg)
%IDENTIFYQUERY The online entry point: audio in, identification decision out.
%
%   Resolves the query config for the clip length, extracts the fingerprint,
%   looks up postings, aligns time offsets, scores candidates and applies
%   the
%   open-set rule.
%
%   Returns res.pred1, .score1, .pred2, .score2, .normScore, .margin,
%   .accepted, .nQueryHashes, .tHashSec, .tMatchSec, plus .offsetHist and
%   .peaks for the GUI figures.
%
%   This is the function the GUI calls and the function the evaluation
%   harness
%   times, so keep display and file I/O out of it entirely.
%
%   Milestone: M1.  Blueprint: section(s) 3.5, 5.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also EXTRACTFINGERPRINT, ALIGNOFFSETS, DECIDEOPENSET.

error('HimigTransform:NotImplemented', ...
    'identifyQuery is a stub (Milestone M1). See docs/designNotes.md.');

end
