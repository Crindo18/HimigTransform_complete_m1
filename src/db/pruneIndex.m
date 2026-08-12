function [Idx, stats] = pruneIndex(Idx, Cfg)
%PRUNEINDEX Drop hashes whose posting lists exceed Cfg.match.maxPostingsPerHash.
%
%   [IDX, STATS] = PRUNEINDEX(IDX, CFG) removes over-common keys from either
%   backend and returns what it did:
%
%       stats.keysBefore, keysAfter, keysDropped, keysDroppedFrac
%       stats.postingsBefore, postingsAfter, postingsDropped, postingsDroppedFrac
%       stats.threshold, stats.maxPostingLenAfter, stats.pruneSec
%
%   WHY. A hash carried by a large fraction of the database contributes almost
%   nothing to discrimination - it fires for every candidate at once, so it
%   raises the floor of the offset histogram without moving the peak - while
%   costing lookup time proportional to its posting count. Dropping it is
%   textbook IR stop-word pruning applied to fingerprints.
%
%   BOTH BACKENDS DROP THE SAME KEY SET. The threshold is a property of the
%   posting counts, which are identical across backends by construction, so
%   the surviving index is identical too. tIndexBackendParity asserts this;
%   without it the pruned benchmark would no longer be like-for-like.
%
%   IDEMPOTENT. Pruning an already-pruned index is a no-op, so it is safe to
%   call from ENROLLDATABASE without tracking whether it has run.
%
%   REPORT THE EFFECT ON BOTH ACCURACY AND MATCH TIME (blueprint 6.5). Pruning
%   is only worth a paragraph in the paper if it is measured on both axes: a
%   threshold aggressive enough to save real time can also remove hashes that
%   a short, noisy query genuinely needed, and the two effects have to be
%   quoted together.
%
%   Milestone: M2.  Blueprint: section 6.5.
%
%   See also BUILDINDEX, BUILDINDEXCSR, BUILDINDEXMAP, INDEXSTATS.

tStart = tic;

if nargin < 2 || isempty(Cfg)
    Cfg = Idx.cfg;
end

threshold = Cfg.match.maxPostingsPerHash;

validateattributes(threshold, {'numeric'}, ...
    {'scalar', 'real', 'positive'}, mfilename, 'Cfg.match.maxPostingsPerHash');

stats                 = struct();
stats.threshold       = threshold;
stats.keysBefore      = numel(Idx.hashKeys);
stats.postingsBefore  = Idx.stats.nHashes;

switch lower(Idx.backend)
    case 'csr'
        [Idx, keep] = pruneCsr(Idx, threshold);
    case 'map'
        [Idx, keep] = pruneMap(Idx, threshold);
    otherwise
        error('HimigTransform:UnknownBackend', ...
            'Index backend "%s" is not recognised.', Idx.backend);
end

stats.keysAfter     = numel(Idx.hashKeys);
stats.keysDropped   = stats.keysBefore - stats.keysAfter;
stats.postingsAfter = Idx.stats.nHashes;
stats.postingsDropped = stats.postingsBefore - stats.postingsAfter;

stats.keysDroppedFrac     = stats.keysDropped     / max(stats.keysBefore, 1);
stats.postingsDroppedFrac = stats.postingsDropped / max(stats.postingsBefore, 1);
stats.maxPostingLenAfter  = Idx.stats.maxPostingLen;
stats.pruneSec            = toc(tStart);

Idx.stats.prunedKeys = Idx.stats.prunedKeys + stats.keysDropped;

if stats.keysDropped == 0
    logMsg('info', ...
        'pruneIndex: nothing above %d postings/key; index unchanged (max was %d).', ...
        threshold, stats.maxPostingLenAfter);
else
    logMsg('info', ...
        ['pruneIndex: dropped %d of %d keys (%.2f%%) and %d of %d postings ' ...
         '(%.2f%%) above %d/key; max posting list now %d. %.2f s.'], ...
        stats.keysDropped, stats.keysBefore, 100 * stats.keysDroppedFrac, ...
        stats.postingsDropped, stats.postingsBefore, ...
        100 * stats.postingsDroppedFrac, threshold, ...
        stats.maxPostingLenAfter, stats.pruneSec);
end

if ~isempty(keep) && ~any(keep)
    logMsg('warn', ...
        ['pruneIndex removed EVERY key. Cfg.match.maxPostingsPerHash = %d is ' ...
         'below the smallest posting list in the index; nothing can match.'], ...
        threshold);
end

end

% =======================================================================
function [Idx, keep] = pruneCsr(Idx, threshold)

if isempty(Idx.hashKeys)
    keep = true(0, 1);
    return
end

bp   = double(Idx.bucketPtr);
lens = bp(2:end) - bp(1:end - 1);
keep = lens <= threshold;

if all(keep)
    return
end

% Rebuild the posting arrays from the surviving buckets. Expanding the kept
% ranges once is cheaper than deleting from the middle of four large arrays.
keepIdx   = find(keep);
keepStart = bp(keepIdx);
keepLen   = lens(keepIdx);

total    = sum(keepLen);
cs       = cumsum(keepLen);
runStart = [1; cs(1:end - 1) + 1];

% Forced to columns for the same reason as in QUERYINDEX: repelem returns a
% row when its first argument is 1x1, and the subtraction would then broadcast
% into a square matrix.
offs = (1:total)' - reshape(repelem(runStart, keepLen), [], 1);
pIdx = reshape(repelem(keepStart, keepLen), [], 1) + offs;

Idx.hashKeys  = Idx.hashKeys(keep);
Idx.songID    = Idx.songID(pIdx);
Idx.t1        = Idx.t1(pIdx);
Idx.bucketPtr = uint32([1; cs + 1]);

Idx.stats.nHashes        = total;
Idx.stats.nDistinct      = numel(Idx.hashKeys);
Idx.stats.meanPostingLen = total / max(numel(Idx.hashKeys), 1);
Idx.stats.maxPostingLen  = maxOr0(keepLen);
Idx.stats.bytes          = 4 * numel(Idx.hashKeys) + 4 * numel(Idx.bucketPtr) ...
                         + 2 * total + 4 * total;

end

% =======================================================================
function [Idx, keep] = pruneMap(Idx, threshold)

if isempty(Idx.hashKeys)
    keep = true(0, 1);
    return
end

keys = Idx.hashKeys;
keep = true(numel(keys), 1);
lens = zeros(numel(keys), 1);

for j = 1:numel(keys)
    lens(j) = size(Idx.map(keys(j)), 1);
end

keep = lens <= threshold;

if all(keep)
    return
end

drop = keys(~keep);
for j = 1:numel(drop)
    remove(Idx.map, drop(j));
end

Idx.hashKeys = keys(keep);
keptLen      = lens(keep);
total        = sum(keptLen);

Idx.stats.nHashes        = total;
Idx.stats.nDistinct      = numel(Idx.hashKeys);
Idx.stats.meanPostingLen = total / max(numel(Idx.hashKeys), 1);
Idx.stats.maxPostingLen  = maxOr0(keptLen);

bytesPerArrayHeader = 100;
Idx.stats.bytes = 6 * total + (4 + bytesPerArrayHeader) * numel(Idx.hashKeys);

end

% =======================================================================
function m = maxOr0(v)

if isempty(v)
    m = 0;
else
    m = max(double(v));
end

end
