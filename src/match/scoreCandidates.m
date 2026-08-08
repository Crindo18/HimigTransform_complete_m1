function [pred, score, normScore, margin] = scoreCandidates(counts, nQueryHashes, Cfg)
%SCORECANDIDATES Rank songs by peak aligned-bin count and compute the decision statistics.
%
%   normScore = score1 / nQueryHashes is the length normalisation: it is
%   what
%   lets a single tau work across 3, 5 and 10 s queries. Verify that
%   empirically; a per-length tau is a legitimate fallback but must be tuned
%   on dev and disclosed.
%
%   margin = score1 / max(score2, 1) is usually more discriminative for
%   open-set rejection than the raw score alone.
%
%   Milestone: M1.  Blueprint: section(s) 3.5.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also ALIGNOFFSETS, DECIDEOPENSET.

error('HimigTransform:NotImplemented', ...
    'scoreCandidates is a stub (Milestone M1). See docs/designNotes.md.');

end
