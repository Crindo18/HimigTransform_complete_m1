function stats = indexStats(Idx, verbose)
%INDEXSTATS Size, density and build-cost statistics for an index.
%
%   STATS = INDEXSTATS(IDX) returns the numbers that go in the backend
%   comparison table in the paper: nHashes, nDistinct, prunedKeys,
%   meanPostingLen, maxPostingLen, buildSec and bytes, plus the derived
%   hashesPerSong and singletonFrac.
%
%   INDEXSTATS(IDX, true) also prints them.
%
%   MEASURED, NOT PREDICTED. Blueprint 2.4 budgets roughly 4.2 M postings and
%   45 MB for the baseline, on an assumed 25 peaks/s. Whether that holds is an
%   empirical question - the achieved peak density depends on the local-max
%   neighbourhood as much as on the density cap - and this function is how you
%   answer it with the real catalogue instead of restating the estimate.
%
%   SINGLETONFRAC is the share of keys holding exactly one posting. It is a
%   useful discriminability read: a healthy fingerprint index is dominated by
%   near-unique keys, and a low value means hashes are colliding across songs
%   and the offset histogram has more noise to reject. It is also the number
%   that says how much PRUNEINDEX will find to remove.
%
%   Milestone: M2.  Blueprint: section 2.4.
%
%   See also BUILDINDEX, PRUNEINDEX, ENROLLDATABASE.

if nargin < 2
    verbose = false;
end

stats = Idx.stats;

stats.backend  = Idx.backend;
stats.cfgTag   = Idx.cfgTag;
stats.nSongs   = stats.nSongsEnrolled;

stats.hashesPerSong = stats.nHashes / max(stats.nSongs, 1);
stats.bytesPerSong  = stats.bytes   / max(stats.nSongs, 1);
stats.megabytes     = stats.bytes / 2^20;

switch lower(Idx.backend)
    case 'csr'
        lens = double(Idx.bucketPtr(2:end)) - double(Idx.bucketPtr(1:end - 1));
        stats.singletonFrac = mean(lens == 1);
        stats.medianPostingLen = median(lens);
        % Base MATLAB only: prctile is Statistics Toolbox, and blueprint 1.2
        % keeps every toolbox call behind a wrapper with a fallback. A plain
        % nearest-rank percentile needs no wrapper at all.
        sorted = sort(lens);
        stats.p99PostingLen = sorted(max(1, ceil(0.99 * numel(sorted))));
    otherwise
        stats.singletonFrac    = NaN;
        stats.medianPostingLen = NaN;
        stats.p99PostingLen    = NaN;
end

if verbose
    fprintf('\n--- Index statistics (%s backend, tag %s) ---\n', ...
        stats.backend, stats.cfgTag);
    fprintf('  songs enrolled      : %d\n',          stats.nSongs);
    fprintf('  postings            : %d\n',          stats.nHashes);
    fprintf('  distinct keys       : %d\n',          stats.nDistinct);
    fprintf('  hashes per song     : %.0f\n',        stats.hashesPerSong);
    fprintf('  postings per key    : mean %.2f, median %.0f, p99 %.0f, max %d\n', ...
        stats.meanPostingLen, stats.medianPostingLen, stats.p99PostingLen, stats.maxPostingLen);
    fprintf('  singleton keys      : %.1f%%\n',      100 * stats.singletonFrac);
    fprintf('  pruned keys         : %d\n',          stats.prunedKeys);
    fprintf('  size                : %.1f MB (%.2f MB/song)\n', ...
        stats.megabytes, stats.bytesPerSong / 2^20);
    fprintf('  build time          : %.2f s\n',      stats.buildSec);
    if isfield(stats, 'enrolSec')
        fprintf('  total enrolment     : %.1f s (%.1f min)\n', ...
            stats.enrolSec, stats.enrolSec / 60);
    end
    fprintf('------------------------------------------------\n');
end

end