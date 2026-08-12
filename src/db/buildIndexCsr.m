function Idx = buildIndexCsr(fpCellArray, songIDs, Cfg)
%BUILDINDEXCSR Sorted CSR-style index: hashKeys + bucketPtr + postings. Default backend.
%
%   IDX = BUILDINDEXCSR(FPCELLARRAY, SONGIDS, CFG) builds the index of
%   blueprint 2.4 from a cell array of fingerprint structs (as returned by
%   EXTRACTFINGERPRINT) and the matching song IDs.
%
%   Structure, borrowed from compressed sparse row:
%
%       Idx.hashKeys   [K x 1] uint32, sorted and unique
%       Idx.bucketPtr  [K+1 x 1] uint32, offsets into the posting arrays
%       Idx.songID     [N x 1] uint16, postings grouped by hash
%       Idx.t1         [N x 1] uint32, postings grouped by hash
%
%   The postings for key k occupy bucketPtr(k) : bucketPtr(k+1)-1. Lookup is a
%   binary search into hashKeys plus a vectorised range expansion, with no
%   per-key object and no per-key allocation.
%
%   WHY THIS RATHER THAN containers.Map. Blueprint D3: at 100 songs the index
%   holds roughly 4 million postings across around 3 million distinct keys. A
%   containers.Map with 'ValueType','any' stores each posting list as its own
%   MATLAB array, and at roughly 100 bytes of header apiece that is several
%   hundred megabytes of pure overhead. Here the same data is four flat
%   numeric arrays - about 45 MB - and building it is one sort rather than
%   three million allocations. BUILDINDEXMAP exists at M2 to make that
%   comparison a measured table rather than an assertion.
%
%   THE SORT IS ON THREE KEYS, NOT ONE. Ordering by (hash, songID, t1) rather
%   than by hash alone costs one extra column and buys determinism: MATLAB's
%   SORT is not documented as stable, so a hash-only sort could order postings
%   within a bucket differently on different machines or releases. Everything
%   downstream sums over a bucket and would not notice - until
%   tIndexBackendParity compares the two backends posting by posting, or two
%   members compare index checksums and find they differ for no reason anyone
%   can explain.
%
%   MEMORY DURING THE BUILD is roughly three times the size of the finished
%   index, because the concatenated triples and their sorted copy coexist.
%   For the 100-song baseline that peaks near 150 MB.
%
%   Milestone: M1 (vertical slice).  Extended at M2 with pruning and stats
%   reporting.  Blueprint: section 2.4.
%
%   See also BUILDINDEX, QUERYINDEX, PRUNEINDEX, INDEXSTATS.

if nargin < 3 || isempty(Cfg)
    Cfg = defaultConfig();
end

tStart = tic;

if ~iscell(fpCellArray)
    fpCellArray = {fpCellArray};
end

nSongs  = numel(fpCellArray);
songIDs = double(songIDs(:));

if numel(songIDs) ~= nSongs
    error('HimigTransform:SongIdCountMismatch', ...
        'Got %d fingerprints but %d song IDs.', nSongs, numel(songIDs));
end

if numel(unique(songIDs)) ~= nSongs
    error('HimigTransform:DuplicateSongId', ...
        'songIDs must be unique - a repeated ID makes two songs indistinguishable in the index.');
end

% ---- Concatenate every posting -----------------------------------------
counts = zeros(nSongs, 1);
for k = 1:nSongs
    counts(k) = numel(fpCellArray{k}.hashes.h);
end

nPost = sum(counts);

allH = zeros(nPost, 1, 'uint32');
allT = zeros(nPost, 1, 'uint32');
at   = 0;

for k = 1:nSongs
    m = counts(k);
    if m == 0
        continue
    end
    allH(at + 1 : at + m) = fpCellArray{k}.hashes.h;
    allT(at + 1 : at + m) = fpCellArray{k}.hashes.t1;
    at = at + m;
end

allS = uint32(repelem(songIDs, counts));

if any(songIDs > double(intmax('uint16')))
    error('HimigTransform:SongIdTooLarge', ...
        'songID %g exceeds uint16, which the posting arrays use (blueprint 2.4).', ...
        max(songIDs));
end

% ---- Sort and derive the CSR structure ---------------------------------
if nPost == 0
    hashKeys  = zeros(0, 1, 'uint32');
    bucketPtr = ones(1, 1, 'uint32');
    postSong  = zeros(0, 1, 'uint16');
    postT1    = zeros(0, 1, 'uint32');
else
    P = sortrows([allH, allS, allT]);

    allH = P(:, 1);
    postSong = uint16(P(:, 2));
    postT1   = P(:, 3);

    newKey    = [true; diff(allH) ~= 0];
    hashKeys  = allH(newKey);
    bucketPtr = uint32([find(newKey); nPost + 1]);
end

% ---- Assemble ----------------------------------------------------------
Idx            = struct();
Idx.backend    = 'csr';
Idx.cfgTag     = Cfg.tag;
Idx.cfg        = Cfg;
Idx.hashKeys   = hashKeys;
Idx.bucketPtr  = bucketPtr;
Idx.songID     = postSong;
Idx.t1         = postT1;
Idx.songIDList = uint16(songIDs);
Idx.nSongs     = max([songIDs; 0]);
Idx.builtOn    = datetime('now');
Idx.matlabVer  = version('-release');

% nSongs is the ADDRESSABLE range, not the enrolled count: ALIGNOFFSETS
% allocates a counts matrix with one row per songID, so it has to cover the
% largest ID in use even when the IDs are not contiguous.
Idx.stats                = struct();
Idx.stats.nSongsEnrolled = nSongs;
Idx.stats.nHashes        = nPost;
Idx.stats.nDistinct      = numel(hashKeys);
Idx.stats.prunedKeys     = 0;
Idx.stats.meanPostingLen = nPost / max(numel(hashKeys), 1);
Idx.stats.maxPostingLen  = maxBucket(bucketPtr);
Idx.stats.buildSec       = toc(tStart);
Idx.stats.bytes          = 4 * numel(hashKeys) + 4 * numel(bucketPtr) ...
                         + 2 * nPost + 4 * nPost;

logMsg('info', ...
    'buildIndexCsr: %d song(s), %d postings, %d distinct keys, mean %.2f/key, %.1f MB, %.2f s.', ...
    nSongs, nPost, numel(hashKeys), Idx.stats.meanPostingLen, ...
    Idx.stats.bytes / 2^20, Idx.stats.buildSec);

end

% =======================================================================
function m = maxBucket(bucketPtr)

if numel(bucketPtr) < 2
    m = 0;
else
    m = max(double(bucketPtr(2:end)) - double(bucketPtr(1:end - 1)));
end

end