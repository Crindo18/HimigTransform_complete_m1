function [h, t1] = makeHashes(peaks, Cfg)
%MAKEHASHES Pair anchor and target peaks and pack them into 32-bit hash codes.
%
%   [H, T1] = MAKEHASHES(PEAKS, CFG) returns uint32 column vectors: H the
%   packed hash of each anchor-target pair, T1 the anchor's frame index.
%
%   For each anchor a, targets b are those peaks with
%
%       Cfg.hash.dtMin <= t_b - t_a <= Cfg.hash.dtMax
%       |f_b - f_a|    <= Cfg.hash.dfMaxBins
%
%   of which the nearest Cfg.hash.fanout by time are kept. Each surviving pair
%   emits (packHash(f_a, f_b, dt), t_a).
%
%   CFG MUST ALREADY BE RESOLVED FOR THE CALLING SIDE. Enrolment passes CFG
%   unchanged; the query path passes RESOLVEQUERYCONFIG(CFG, durationSec).
%   This function does not resolve it itself, because it cannot see how long
%   the clip is and guessing would make Enhancement 2 depend on a heuristic
%   buried three levels down.
%
%   WHY dtMin EXISTS. At dtMin = 0 an anchor pairs with peaks in its own
%   frame, producing hashes whose time delta carries no information and which
%   therefore collide across every song in the catalogue. They cost index
%   space and contribute nothing but noise to the offset histogram.
%
%   WHY "NEAREST BY TIME" IS FREE. PICKPEAKSFIXED emits peaks in frame order
%   and ENFORCEPEAKDENSITY restores that order, so the candidate window is
%   already sorted by time - the first fanout survivors of the frequency test
%   ARE the nearest ones. That ordering is also what lets the anchor sweep
%   below advance two pointers monotonically instead of searching, which turns
%   an O(P^2) pairing into something linear in the number of pairs actually
%   emitted.
%
%   THE HEADROOM ARGUMENT FOR ENHANCEMENT 2. A 3 s query at 25 peaks/s holds
%   about 75 peaks, so C(75,2) is roughly 2,775 possible pairs. Fan-out 8
%   uses about 600 of them; fan-out 20 uses about 1,500. The pairs are there
%   to be taken, which is why widening the query-side fan-out for short clips
%   is close to free and why it belongs in the paper as a mechanism rather
%   than as a tuning result.
%
%   Milestone: M1.  Blueprint: section 3.4.
%
%   See also PACKHASH, RESOLVEQUERYCONFIG, PICKPEAKS.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end

tIdx = double(peaks.tIdx);
fIdx = double(peaks.fIdx);

P = numel(tIdx);

if P == 0
    h  = zeros(0, 1, 'uint32');
    t1 = zeros(0, 1, 'uint32');
    return
end

if any(diff(tIdx) < 0)
    error('HimigTransform:PeaksNotTimeSorted', ...
        ['makeHashes requires peaks in ascending frame order. Something ' ...
         'downstream of pickPeaks reordered them.']);
end

dtMin     = Cfg.hash.dtMin;
dtMax     = Cfg.hash.dtMax;
dfMaxBins = Cfg.hash.dfMaxBins;
fanout    = Cfg.hash.fanout;

if dtMax < dtMin
    error('HimigTransform:BadTargetZone', ...
        'Cfg.hash.dtMax (%d) is below dtMin (%d) - the target zone is empty.', ...
        dtMax, dtMin);
end

hBuf  = zeros(P * fanout, 1, 'uint32');
t1Buf = zeros(P * fanout, 1, 'uint32');
n     = 0;

lo = 1;
hi = 1;

for a = 1:P
    ta = tIdx(a);
    fa = fIdx(a);

    tLo = ta + dtMin;
    tHi = ta + dtMax;

    % Two monotone pointers. ta is non-decreasing in a, so tLo and tHi are
    % too, so neither pointer ever moves backwards and the whole sweep costs
    % one pass over the peak list.
    while lo <= P && tIdx(lo) < tLo
        lo = lo + 1;
    end
    if hi < lo
        hi = lo;
    end
    while hi <= P && tIdx(hi) <= tHi
        hi = hi + 1;
    end

    if hi <= lo
        continue
    end

    cand = (lo:(hi - 1))';
    cand = cand(abs(fIdx(cand) - fa) <= dfMaxBins);

    if isempty(cand)
        continue
    end
    if numel(cand) > fanout
        cand = cand(1:fanout);      % already time-ordered, so these are nearest
    end

    m = numel(cand);
    hBuf(n + 1 : n + m)  = packHash(fa, fIdx(cand), tIdx(cand) - ta, Cfg);
    t1Buf(n + 1 : n + m) = ta;
    n = n + m;
end

h  = hBuf(1:n);
t1 = t1Buf(1:n);

end