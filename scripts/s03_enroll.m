%S03_ENROLL  Fingerprint the 100 in-database songs and build the baseline index.
%
%   Enrols every catalog row with role = db under baselineConfig, writes
%   db/index_<baselineTag>.mat, and checks the M2 exit criteria:
%
%       - 100 songs enrolled
%       - >= 95% top-1 on clean 10 s queries
%       - enrolment under 15 minutes
%       - median match time under 1 s
%
%   BASELINE ONLY, FOR NOW. Blueprint D4 calls for index_baseline and
%   index_enhanced from the same extraction run, and that is right - but
%   enhancedConfig sets peaks.mode = 'adaptive', which needs pickPeaksAdaptive
%   (M4). Building the enhanced index is therefore an M5 step, and this script
%   grows one section when those functions land. Nothing here needs to change
%   for that: the enrolment path is already config-driven.
%
%   Idempotent. Fingerprints are cached per song under
%   db/fingerprints/<cfgTag>/, so a re-run after a code change re-extracts
%   only what actually changed. The cache is keyed by config tag AND by each
%   song's checksum, so it invalidates itself rather than going stale.
%
%   Milestone: M2.  Blueprint: sections 0 (D4), 2.3, 2.4, 6.3, 7 (M2).
%
%   Usage:
%       setupPaths;
%       s03_enroll

projRoot = setupPaths();
Cfg      = baselineConfig();
rng(Cfg.seed, 'twister');

logMsg('info', '===== s03_enroll =====');
logMsg('info', 'MATLAB %s | config tag %s', version('-release'), Cfg.tag);

catalog = loadCatalog(Cfg);

% =======================================================================
% 1. Enrol
% =======================================================================
[Idx, enrolReport] = enrollDatabase(catalog, Cfg);

indexPath = fullfile(projRoot, 'db', sprintf('index_%s.mat', Cfg.tag));
save(indexPath, 'Idx', '-v7.3');
logMsg('info', 'Index written to %s', indexPath);

reportPath = fullfile(projRoot, 'db', 'enrolReport.csv');
writetable(enrolReport, reportPath);

stats = indexStats(Idx, true);

% =======================================================================
% 2. Peak density, measured on real music
% =======================================================================
% Blueprint 3.3 sets a target of Cfg.peaks.densityPerSec. Whether it is
% reached is a property of the local-max neighbourhood as much as of the
% density cap, so it is measured rather than assumed. The achieved rate also
% drives the index-size budget in blueprint 2.4, and it is the baseline that
% the M4 "peaks/second vs SNR" mechanism figure is drawn against.
okRows = enrolReport.action ~= "failed";
dens   = enrolReport.densityPerSec(okRows);

enrolledIDs = double(enrolReport.songID(okRows));

audit       = peakBudgetAudit(Cfg);
nbhdCeiling = audit.ceilingPerSec;

fprintf('\n--- Peak density (target %.0f/s) ---\n', Cfg.peaks.densityPerSec);
fprintf('  achieved  : mean %.1f/s, median %.1f/s, range %.1f - %.1f\n', ...
    mean(dens), median(dens), min(dens), max(dens));
fprintf('  local-max ceiling for nbhd %dx%d: %.1f/s\n', ...
    Cfg.peaks.nbhdF, Cfg.peaks.nbhdT, nbhdCeiling);
if nbhdCeiling < Cfg.peaks.densityPerSec
    fprintf('  NOTE: the target is above the geometric ceiling, so the density cap\n');
    fprintf('        cannot bind. Shrinking nbhdF/nbhdT is what raises density.\n');
end

fprintf('\n--- Index size vs blueprint 2.4 budget ---\n');
fprintf('  predicted : ~4.2 M postings, ~45 MB (at 25 peaks/s, fan-out %d)\n', Cfg.hash.fanout);
fprintf('  measured  : %.2f M postings, %.1f MB\n', stats.nHashes / 1e6, stats.megabytes);

% =======================================================================
% 3. Clean 10 s accuracy and timing - the M2 exit criteria
% =======================================================================
dbRows = catalog(catalog.role == 'db', :);
nDb    = height(dbRows);

correct  = false(nDb, 1);
tTotal   = zeros(nDb, 1);
normSc   = zeros(nDb, 1);
marg     = zeros(nDb, 1);

lenSamp = 10 * Cfg.audio.fs;
warmup  = 5;   % blueprint 6.3: discard cold calls, they measure the JIT

logMsg('info', 'Checking clean 10 s top-1 accuracy over %d songs...', nDb);

for k = 1:nDb
    f = fullfile(projRoot, 'data', 'processed', ...
        strrep(char(dbRows.procPath(k)), '/', filesep));
    if ~isfile(f)
        continue
    end

    x  = audioread(f);
    x  = x(:, 1);
    i0 = max(1, floor(numel(x) / 3));
    seg = x(i0 : min(i0 + lenSamp - 1, numel(x)));

    res = identifyQuery(seg, Idx, Cfg);

    correct(k) = res.pred1 == double(dbRows.songID(k));
    tTotal(k)  = res.tTotalSec;
    normSc(k)  = res.normScore;
    marg(k)    = res.margin;

    if mod(k, 25) == 0
        logMsg('info', '  %d/%d checked (%.1f%% correct so far).', ...
            k, nDb, 100 * mean(correct(1:k)));
    end
end

acc = mean(correct);

% Only songs that actually ran contribute a timing. A missing processed file
% leaves a zero behind, and zeros would drag the median down and make the
% sub-1 s criterion look satisfied when it had not been measured.
timed = tTotal(tTotal > 0);
if numel(timed) > warmup
    timed = timed(warmup + 1 : end);
end
medTime = median(timed);
sortedT  = sort(timed);
p95Time  = sortedT(max(1, ceil(0.95 * numel(sortedT))));

fprintf('\n--- Clean 10 s queries (%d songs) ---\n', nDb);
fprintf('  top-1 accuracy : %.1f%% (%d/%d)\n', 100 * acc, nnz(correct), nDb);
fprintf('  normScore      : median %.4f, min %.4f\n', median(normSc), min(normSc));
fprintf('  margin         : median %.1f, min %.1f\n', median(marg), min(marg));
fprintf('  match time     : median %.3f s, p95 %.3f s (warm-up %d discarded)\n', ...
    medTime, p95Time, warmup);
fprintf('  (index load excluded - that is a one-time startup cost)\n');

if any(~correct)
    fprintf('\n  Misidentified songIDs: %s\n', ...
        strjoin(string(double(dbRows.songID(~correct)))', ', '));
end

% =======================================================================
% Exit checks
% =======================================================================
problems = strings(0, 1);

if stats.nSongs < 100
    problems(end + 1) = sprintf("only %d song(s) enrolled, expected 100", stats.nSongs); %#ok<SAGROW>
end
if any(enrolReport.action == "failed")
    problems(end + 1) = sprintf("%d song(s) failed to fingerprint", ...
        nnz(enrolReport.action == "failed")); %#ok<SAGROW>
end
if acc < 0.95
    problems(end + 1) = sprintf("clean 10 s top-1 accuracy %.1f%% is below 95%%", 100 * acc); %#ok<SAGROW>
end
if Idx.stats.enrolSec > 15 * 60
    problems(end + 1) = sprintf("enrolment took %.1f min, over the 15 min budget", ...
        Idx.stats.enrolSec / 60); %#ok<SAGROW>
end
if medTime > 1.0
    problems(end + 1) = sprintf("median match time %.3f s exceeds 1 s", medTime); %#ok<SAGROW>
end

% =======================================================================
% Backend comparison and pruning (blueprint D3, 6.5)
% =======================================================================
% The proposal names containers.Map in its methodology; the project defaults
% to a CSR index for speed. That substitution is only defensible if the two
% are measured against each other on the SAME database and shown to return
% identical postings - which is what turns a deviation into a reported
% finding. tIndexBackendParity holds the identical-postings half; this block
% produces the numbers.
%
% Set HIMIG_SKIP_MAP=1 to skip it. The map backend is slow to build by
% design, and there is no reason to pay that cost on every re-run once the
% table is recorded.
runBackendComparison = isempty(getenv('HIMIG_SKIP_MAP'));

if runBackendComparison
    fprintf('\n--- Backend comparison (blueprint D3) ---\n');

    CfgMap = Cfg;
    CfgMap.index.backend = 'map';

    fpCells = cell(numel(enrolledIDs), 1);
    for k = 1:numel(enrolledIDs)
        fpCells{k} = loadFingerprint(enrolledIDs(k), Cfg);
    end

    tMap  = tic;
    IdxMap = buildIndexMap(fpCells, enrolledIDs, CfgMap);
    mapBuildSec = toc(tMap);

    % MEMORY IS ESTIMATED, NOT MEASURED BY WHOS. containers.Map is a HANDLE
    % class, so whos reports the size of the handle and never recurses into
    % the stored value arrays. On the real database that produced ~2 MB for a
    % map holding 610,999 posting arrays - which is roughly the size of the
    % key array alone, and it made the printed table say the proposal's
    % backend used a FIFTH of the CSR memory. That is the exact opposite of
    % blueprint D3's finding, printed directly underneath the buildIndexMap
    % log line reporting the honest number.
    %
    % buildIndexMap computes that number: postings plus MATLAB's per-array
    % header on every value array, which is the whole cost being reported.
    % Label it estimated so nobody mistakes it for a measurement.
    csrWhos   = whos('Idx');
    csrBytes  = csrWhos.bytes;
    mapBytes  = IdxMap.stats.bytes;

    fprintf('  %-22s %14s %14s\n', '', 'csr', 'containers.Map');
    fprintf('  %-22s %14d %14d\n', 'postings', ...
        Idx.stats.nHashes, IdxMap.stats.nHashes);
    fprintf('  %-22s %14d %14d\n', 'distinct keys', ...
        Idx.stats.nDistinct, IdxMap.stats.nDistinct);
    fprintf('  %-22s %13.2fs %13.2fs\n', 'build time', ...
        Idx.stats.buildSec, mapBuildSec);
    fprintf('  %-22s %13.1fM %12.1fM*\n', 'in-memory', ...
        csrBytes / 2^20, mapBytes / 2^20);
    fprintf('  %-22s %13.1fx\n', 'map / csr memory', ...
        mapBytes / max(csrBytes, 1));
    fprintf('  %-22s %s\n', '', '* estimated - whos cannot size a handle class');

    % Same query through both, to confirm parity on the real database rather
    % than only on the five toy songs the unit test uses.
    probeID  = enrolledIDs(1);
    probeSig = audioread(fullfile(projRoot, 'data', 'processed', ...
        strrep(char(catalog.procPath(catalog.songID == probeID)), '/', filesep)));
    probeQ   = probeSig(1 : min(10 * Cfg.audio.fs, numel(probeSig)));

    rc = identifyQuery(probeQ, Idx,    Cfg);
    rm = identifyQuery(probeQ, IdxMap, CfgMap);

    if rc.pred1 == rm.pred1 && rc.score1 == rm.score1
        fprintf('  parity on real DB      : OK (both -> songID %d, score %d)\n', ...
            rc.pred1, rc.score1);
    else
        fprintf('  parity on real DB      : MISMATCH (csr %d/%d vs map %d/%d)\n', ...
            rc.pred1, rc.score1, rm.pred1, rm.score1);
        problems(end + 1) = "backend parity failed on the real database"; %#ok<SAGROW>
    end

    clear IdxMap fpCells
else
    fprintf('\n--- Backend comparison skipped (HIMIG_SKIP_MAP set) ---\n');
end

% ---- Pruning ------------------------------------------------------------
% Reported, not applied. Pruning changes what the index can match, so it does
% not silently enter a baseline that M3 is about to freeze. Turn it on only
% after the accuracy and match-time effect has been measured on both axes.
[~, pruneStats] = pruneIndex(Idx, Cfg);

fprintf('\n--- Pruning at maxPostingsPerHash = %d (measured, NOT applied) ---\n', ...
    Cfg.match.maxPostingsPerHash);
fprintf('  keys over threshold : %d of %d (%.2f%%)\n', ...
    pruneStats.keysDropped, pruneStats.keysBefore, 100 * pruneStats.keysDroppedFrac);
fprintf('  postings removed    : %d of %d (%.2f%%)\n', ...
    pruneStats.postingsDropped, pruneStats.postingsBefore, ...
    100 * pruneStats.postingsDroppedFrac);
if pruneStats.keysDropped == 0
    fprintf('  The threshold is inert on this database (largest list %d).\n', ...
        Idx.stats.maxPostingLen);
    fprintf('  Lower it only with an accuracy AND match-time measurement.\n');
end

fprintf('\n--- M2 exit check ---\n');
fprintf('Songs enrolled          : %d\n',      stats.nSongs);
fprintf('Clean 10 s top-1        : %.1f%%\n',  100 * acc);
fprintf('Enrolment time          : %.1f min\n', Idx.stats.enrolSec / 60);
fprintf('Median match time       : %.3f s\n',  medTime);
fprintf('Index                   : %s\n',      indexPath);

if isempty(problems)
    fprintf('s03_enroll: PASS\n');
    fprintf('Record these numbers - the backend comparison table needs them (blueprint 2.4).\n');
else
    fprintf('s03_enroll: BLOCKED\n');
    for k = 1:numel(problems)
        fprintf('  - %s\n', problems(k));
    end
end
fprintf('---------------------\n');