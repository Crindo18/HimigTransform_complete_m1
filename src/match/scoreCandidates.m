function [pred, score, normScore, margin] = scoreCandidates(counts, nQueryHashes, Cfg)
%SCORECANDIDATES Rank songs by peak aligned-bin count and compute the decision statistics.
%
%   [PRED, SCORE, NORMSCORE, MARGIN] = SCORECANDIDATES(COUNTS, NQUERYHASHES,
%   CFG) ranks the rows of COUNTS by their largest bin and returns the top
%   Cfg.match.topK song IDs in PRED with their scores in SCORE, both descending.
%   PRED(1) and SCORE(1) are the top-1; PRED(2) and SCORE(2) the runner-up.
%
%       normScore = score1 / nQueryHashes
%       margin    = score1 / max(score2, 1)
%
%   THE SCORE IS A MAXIMUM, NOT A SUM, for the reason set out in ALIGNOFFSETS:
%   the evidence is agreement on one offset, not collision volume.
%
%   NORMALISATION IS WHAT MAKES ONE TAU WORK ACROSS LENGTHS. A 10 s query
%   emits roughly three times the hashes of a 3 s query, so its raw score is
%   about three times larger for the same quality of match. An absolute
%   threshold would then be simultaneously too strict at 3 s and too loose at
%   10 s, and every accuracy-versus-length curve would be measuring the
%   threshold instead of the system. Dividing by nQueryHashes gives a
%   dimensionless "fraction of my hashes that agreed on one offset."
%
%   Verify that empirically rather than assuming it. A per-length tau is a
%   legitimate fallback, but it has to be tuned on dev and disclosed.
%
%   MARGIN IS USUALLY THE BETTER REJECTION STATISTIC. normScore says how well
%   the best song did; margin says whether anything else came close. A holdout
%   song genuinely absent from the database tends to produce several mediocre
%   candidates of similar strength - margin near 1 - even when noise has
%   pushed normScore into a range a real match could occupy. The two
%   statistics fail in different directions, which is why DECIDEOPENSET
%   requires both.
%
%   TAU AND RHO MUST BE RE-TUNED PER SYSTEM. The enhanced configuration emits
%   more hashes per second, so nQueryHashes grows and normScore shifts under a
%   threshold that was calibrated on the baseline. Reusing the baseline
%   numbers is the easiest way to publish a gain that is really a threshold
%   artifact.
%
%   NO MATCH AT ALL returns PRED = 0, SCORE = 0, NORMSCORE = 0, MARGIN = 0.
%   Ties break toward the lower songID, deterministically.
%
%   Milestone: M1.  Blueprint: section 3.5.
%
%   See also ALIGNOFFSETS, DECIDEOPENSET.

if nargin < 3 || isempty(Cfg)
    Cfg = defaultConfig();
end

nQueryHashes = double(nQueryHashes);

if isempty(counts) || nnz(counts) == 0
    pred      = 0;
    score     = 0;
    normScore = 0;
    margin    = 0;
    return
end

rowMax = full(max(counts, [], 2));

K = min(Cfg.match.topK, numel(rowMax));

[sorted, ord] = sort(rowMax, 'descend');

pred  = ord(1:K);
score = sorted(1:K);

% Songs with no evidence are not candidates; reporting them as ranked
% predictions would put an arbitrary songID in the GUI's results table.
pred(score == 0) = 0;

score1 = score(1);

if numel(score) >= 2
    score2 = score(2);
else
    score2 = 0;
end

normScore = score1 / max(nQueryHashes, 1);
margin    = score1 / max(score2, 1);

end