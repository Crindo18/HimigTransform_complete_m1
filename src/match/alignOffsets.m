function [counts, offsetInfo] = alignOffsets(post, Tq, nSongs, Cfg)
%ALIGNOFFSETS Histogram time-offset differences per candidate song.
%
%   COUNTS = ALIGNOFFSETS(POST, TQ, NSONGS, CFG) returns a sparse
%   [NSONGS x nOffsets] matrix of aligned-hash counts. TQ holds the query-side
%   anchor frame of each query hash, so
%
%       delta = t1_ref - Tq(post.qIdx)
%
%   is the constant frame offset a genuine match must produce. The deltas are
%   shifted into a positive range and accumulated per song.
%
%   [COUNTS, OFFSETINFO] = ALIGNOFFSETS(...) also returns the axis needed to
%   read the matrix: offsetInfo.deltaMin, .nOffsets and .deltaFrames, so a
%   column index can be turned back into a real frame offset. The GUI's offset
%   histogram needs that, and recomputing it in the caller would mean two
%   copies of the same shift convention.
%
%   THIS STEP IS THE WHOLE ALGORITHM. Hash collisions alone say almost
%   nothing - unrelated songs share plenty of (f1, f2, dt) triples, and a
%   large catalogue guarantees it. What distinguishes the right song is that
%   ITS collisions all agree on a single delta, because the query really is a
%   contiguous excerpt sitting at one fixed place in the reference. Wrong
%   songs scatter their collisions across every offset. A tall spike beats a
%   broad smear even when the smear holds more total collisions, which is
%   exactly why the score is the maximum bin and not the sum.
%
%   SMOOTHING IS TOP-K ONLY. A peak that should be one bin tall gets split
%   across two when the excerpt does not start on a frame boundary - which is
%   almost always, since the query start is a sample offset and frames are 256
%   samples apart. Summing over +/- Cfg.match.offsetTolFrames puts it back
%   together. Doing that to the entire sparse matrix would touch millions of
%   structurally empty cells to fix twenty rows that matter, so only the top
%   Cfg.match.topK songs by raw peak are smoothed.
%
%   That shortcut is safe rather than merely convenient: smoothing can only
%   raise a row's maximum, and a song outside the top K already has a raw
%   maximum no higher than every song inside it. So no song can overtake the
%   smoothed leaders without having been smoothed itself, and the top-1 and
%   top-2 that SCORECANDIDATES reads are always correct as long as topK >= 2.
%
%   Milestone: M1.  Blueprint: section 3.5.
%
%   See also QUERYINDEX, SCORECANDIDATES.

if nargin < 4 || isempty(Cfg)
    Cfg = defaultConfig();
end

nSongs = double(nSongs);
Tq     = double(Tq(:));

if isempty(post.qIdx)
    counts     = sparse(nSongs, 1);
    offsetInfo = struct('deltaMin', 0, 'nOffsets', 1, 'deltaFrames', 0);
    return
end

songID = double(post.songID(:));
delta  = double(post.t1(:)) - Tq(double(post.qIdx(:)));

deltaMin = min(delta);
off      = delta - deltaMin + 1;
nOffsets = max(off);

% ---- Raw histogram ------------------------------------------------------
counts = accumarray([songID, off], 1, [nSongs, nOffsets], @sum, 0, true);

% ---- Smooth the contenders only ----------------------------------------
tol = Cfg.match.offsetTolFrames;

if tol > 0 && nOffsets > 1
    rowMax = full(max(counts, [], 2));
    K      = min(Cfg.match.topK, nnz(rowMax));

    if K > 0
        [~, topSongs] = maxk(rowMax, K);

        sub = full(counts(topSongs, :));
        sub = movsum(sub, 2 * tol + 1, 2);

        counts(topSongs, :) = sparse(sub);
    end
end

offsetInfo             = struct();
offsetInfo.deltaMin    = deltaMin;
offsetInfo.nOffsets    = nOffsets;
offsetInfo.deltaFrames = (deltaMin : deltaMin + nOffsets - 1)';

end