function Idx = buildIndexMap(fpCellArray, songIDs, Cfg)
%BUILDINDEXMAP containers.Map hash index - the proposal-faithful backend.
%
%   IDX = BUILDINDEXMAP(FPCELLARRAY, SONGIDS, CFG) stores the fingerprint
%   database as the proposal specifies: a containers.Map from packed hash to
%   the list of (songID, anchorFrame) pairs carrying it.
%
%       Idx.map   containers.Map('KeyType','uint32','ValueType','any')
%                 key   = packed hash
%                 value = [m x 2] uint32 of [songID, t1]
%
%   BUILT IN ONE SHOT, DELIBERATELY. The natural way to write this is
%
%       for each posting
%           M(key) = [M(key); newRow];       % <-- never do this
%
%   which is quadratic: MATLAB reallocates the whole value array on every
%   append, and at 1.4 M postings it does not finish in usable time. Instead
%   the postings are concatenated, sorted once, split on run lengths with
%   MAT2CELL, and handed to the containers.Map constructor in a single call.
%
%   IDENTICAL POSTINGS TO BUILDINDEXCSR. The sort key is (hash, songID, t1),
%   exactly as in the CSR backend, so QUERYINDEX returns the same rows in the
%   same order from either. tIndexBackendParity asserts it. Without that
%   guarantee the benchmark compares two different systems and the
%   scalability claim in the paper collapses.
%
%   WHY BOTH BACKENDS EXIST (blueprint D3). The proposal names containers.Map
%   in its methodology. It is an implementation detail with a real cost at 100
%   songs: every value is a separate MATLAB array carrying its own header, so
%   the map pays on the order of 100 bytes per KEY on top of 6 bytes of actual
%   posting data, and lookup has no vectorised form. Keeping both backends
%   behind one interface turns that from a deviation to hide into a
%   measurement to report.
%
%   Milestone: M2.  Blueprint: sections 0 (D3), 2.4.
%
%   See also BUILDINDEX, BUILDINDEXCSR, QUERYINDEX, INDEXSTATS.

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

if any(songIDs > double(intmax('uint16')))
    error('HimigTransform:SongIdTooLarge', ...
        'songID %g exceeds uint16, which the posting arrays use (blueprint 2.4).', ...
        max(songIDs));
end

% ---- Concatenate every posting -----------------------------------------
counts = zeros(nSongs, 1);
for k = 1:nSongs
    fp = fpCellArray{k};

    if ~isfield(fp, 'hashes')
        error('HimigTransform:BadFingerprint', ...
            'Entry %d is not a fingerprint struct (no hashes field).', k);
    end

    if isfield(fp, 'cfgTag') && ~isempty(fp.cfgTag) && ~strcmp(fp.cfgTag, Cfg.tag)
        error('HimigTransform:ConfigTagMismatch', ...
            ['Fingerprint %d was built with config "%s" but the index is ' ...
             'being built with "%s". A stale cache mixed into a fresh index ' ...
             'produces an index that looks healthy and matches nothing.'], ...
            k, fp.cfgTag, Cfg.tag);
    end

    counts(k) = numel(fp.hashes.h);
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
    allH(at + 1 : at + m) = fpCellArray{k}.hashes.h(:);
    allT(at + 1 : at + m) = fpCellArray{k}.hashes.t1(:);
    at = at + m;
end

allS = uint32(repelem(songIDs, counts));
allS = allS(:);

% ---- Sort once, split on run lengths, construct once --------------------
if nPost == 0
    map       = containers.Map('KeyType', 'uint32', 'ValueType', 'any');
    hashKeys  = zeros(0, 1, 'uint32');
    bucketLen = zeros(0, 1);
else
    P = sortrows([allH, allS, allT]);

    sortedH = P(:, 1);
    values  = P(:, 2:3);

    newKey    = [true; diff(sortedH) ~= 0];
    hashKeys  = sortedH(newKey);
    startIdx  = find(newKey);
    bucketLen = diff([startIdx; nPost + 1]);

    valueCells = mat2cell(values, bucketLen, 2);

    map = containers.Map(num2cell(hashKeys), valueCells, 'UniformValues', false);
end

% ---- Assemble ----------------------------------------------------------
Idx            = struct();
Idx.backend    = 'map';
Idx.cfgTag     = Cfg.tag;
Idx.cfg        = Cfg;
Idx.map        = map;
Idx.hashKeys   = hashKeys;
Idx.songIDList = uint16(songIDs);
Idx.nSongs     = max([songIDs; 0]);
Idx.builtOn    = datetime('now');
Idx.matlabVer  = version('-release');

% nSongs is the ADDRESSABLE range, not the enrolled count - the same
% convention as BUILDINDEXCSR, because ALIGNOFFSETS allocates one row per
% songID and the IDs stop being contiguous as soon as the holdout songs take
% their share of the catalogue.
Idx.stats                = struct();
Idx.stats.nSongsEnrolled = nSongs;
Idx.stats.nHashes        = nPost;
Idx.stats.nDistinct      = numel(hashKeys);
Idx.stats.prunedKeys     = 0;
Idx.stats.meanPostingLen = nPost / max(numel(hashKeys), 1);
Idx.stats.maxPostingLen  = maxOr0(bucketLen);
Idx.stats.buildSec       = toc(tStart);

% Payload plus MATLAB's per-array overhead. Every value is a separate array
% carrying its own header, which is the whole reason for measuring this
% backend rather than assuming it matches CSR. The constant is nominal -
% report it as an estimate and quote the measured workspace size from WHOS
% alongside it in the paper.
bytesPerArrayHeader = 100;
Idx.stats.bytes     = 6 * nPost + (4 + bytesPerArrayHeader) * numel(hashKeys);
Idx.stats.bytesNote = 'estimated; per-value array overhead assumed 100 B/key';

logMsg('info', ...
    'buildIndexMap: %d song(s), %d postings, %d distinct keys, mean %.2f/key, ~%.1f MB, %.2f s.', ...
    nSongs, nPost, numel(hashKeys), Idx.stats.meanPostingLen, ...
    Idx.stats.bytes / 2^20, Idx.stats.buildSec);

end

% =======================================================================
function m = maxOr0(v)

if isempty(v)
    m = 0;
else
    m = max(double(v));
end

end
