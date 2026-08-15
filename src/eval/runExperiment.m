function R = runExperiment(M, Idx, Cfg, systemName, varargin)
%RUNEXPERIMENT Evaluate a query manifest against an index, one row per query.
%
%   R = RUNEXPERIMENT(M, IDX, CFG, SYSTEMNAME) synthesises every query in the
%   manifest M, identifies it against IDX, and returns the long-format results
%   table of blueprint 2.6. Long format, not wide: every figure is then a
%   GROUPSUMMARY away.
%
%   R = RUNEXPERIMENT(..., 'Name', VALUE) accepts
%       'Catalog'    catalog table (default: LOADCATALOG)
%       'UseParfor'  parallelise the grid (default false - see below)
%       'WarmupN'    calls marked as warm-up (default 5, blueprint 6.3)
%       'LogEvery'   progress line every N queries (default 500)
%
%   WARM-UP IS MARKED, NOT DROPPED. Blueprint 6.3 says discard the first five
%   calls, because tic/toc on a cold call measures MATLAB's JIT rather than
%   the algorithm. Discarding them here would throw away five perfectly good
%   accuracy observations to fix a timing problem, so the rows stay and carry
%   a 'warmup' flag; COMPUTEMETRICS excludes them from timing statistics only.
%
%   PARFOR IS OFF BY DEFAULT. It is the right way to run the grid for
%   accuracy (blueprint 8.1) and the wrong way to measure latency: workers
%   contend, and the per-query times that come back cannot support success
%   criterion 3. Run once serially for the timing table, once with parfor for
%   the accuracy grid, or accept the longer serial run. Timing rows from a
%   parfor run are flagged in R.Properties.UserData.
%
%   HOLDOUT ROWS CARRY isInDb = false. Their ground-truth songID is not in the
%   index, so pred1 can never equal it and 'correct' is meaningless for them.
%   Blueprint 8.3 defines closed-set accuracy and recall over in-DB queries
%   and FAR over holdout queries; keeping both in one table with a flag is
%   what lets COMPUTEMETRICS compute all of them from a single run.
%
%   Milestone: M3.  Blueprint: section(s) 2.6, 6.3, 6.4, 8.1, 8.3.
%
%   See also BUILDQUERYMANIFEST, SYNTHESIZEQUERY, IDENTIFYQUERY, COMPUTEMETRICS.

p = inputParser;
p.addParameter('Catalog',   [],    @(v) isempty(v) || istable(v));
p.addParameter('UseParfor', false, @(v) islogical(v) && isscalar(v));
p.addParameter('WarmupN',   5,     @(v) isnumeric(v) && isscalar(v) && v >= 0);
p.addParameter('LogEvery',  500,   @(v) isnumeric(v) && isscalar(v) && v > 0);
p.parse(varargin{:});
opt = p.Results;

if isempty(opt.Catalog)
    catalog = loadCatalog();
else
    catalog = opt.Catalog;
end

n = height(M);
if n == 0
    error('HimigTransform:EmptyManifest', 'runExperiment received an empty manifest.');
end

logMsg('info', 'runExperiment: %s, %d quer(ies), index tag %s.', ...
    systemName, n, Idx.cfgTag);

% ---- Preallocate --------------------------------------------------------
pred1           = zeros(n, 1, 'uint16');
score1          = zeros(n, 1);
pred2           = zeros(n, 1, 'uint16');
score2          = zeros(n, 1);
normScore       = zeros(n, 1);
margin          = zeros(n, 1);
accepted        = false(n, 1);
correct         = false(n, 1);
nQueryHashes    = zeros(n, 1);
nCandidateSongs = zeros(n, 1);
snrDbMeasured   = zeros(n, 1);
tHashSec        = zeros(n, 1);
tMatchSec       = zeros(n, 1);
tTotalSec       = zeros(n, 1);
warmup          = false(n, 1);
warmup(1:min(opt.WarmupN, n)) = true;

isInDb = M.role == 'db';

tAll = tic;

if opt.UseParfor
    parfor k = 1:n
        [pred1(k), score1(k), pred2(k), score2(k), normScore(k), margin(k), ...
         accepted(k), nQueryHashes(k), nCandidateSongs(k), snrDbMeasured(k), ...
         tHashSec(k), tMatchSec(k), tTotalSec(k)] = ...
            runOne(M(k, :), catalog, Idx, Cfg, []);
    end
else
    % One audio cache for the whole serial run. Sorting the manifest by song
    % would bound its size; at 120 songs of 8 kHz mono the whole corpus is
    % roughly 200 MB, so it is simpler to let it fill.
    cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for k = 1:n
        [pred1(k), score1(k), pred2(k), score2(k), normScore(k), margin(k), ...
         accepted(k), nQueryHashes(k), nCandidateSongs(k), snrDbMeasured(k), ...
         tHashSec(k), tMatchSec(k), tTotalSec(k)] = ...
            runOne(M(k, :), catalog, Idx, Cfg, cache);

        if mod(k, opt.LogEvery) == 0 || k == n
            seen = isInDb(1:k);
            if any(seen)
                acc = 100 * mean(pred1(seen) == M.songID(seen));
                logMsg('info', '  %d/%d queries (in-DB top-1 %.1f%% so far, %.0f s elapsed).', ...
                    k, n, acc, toc(tAll));
            else
                logMsg('info', '  %d/%d queries (%.0f s elapsed).', k, n, toc(tAll));
            end
        end
    end
end

correct(isInDb) = pred1(isInDb) == M.songID(isInDb);

elapsed = toc(tAll);

R = table(M.queryID, M.songID, M.repertoire, M.role, M.split, ...
    M.lengthSec, M.noiseType, M.targetSnrDb, ...
    repmat(string(systemName), n, 1), repmat(string(Cfg.tag), n, 1), ...
    isInDb, pred1, score1, pred2, score2, normScore, margin, ...
    accepted, correct, nQueryHashes, nCandidateSongs, snrDbMeasured, ...
    warmup, tHashSec, tMatchSec, tTotalSec, ...
    'VariableNames', {'queryID', 'songID', 'repertoire', 'role', 'split', ...
    'lengthSec', 'noiseType', 'targetSnrDb', 'system', 'cfgTag', ...
    'isInDb', 'pred1', 'score1', 'pred2', 'score2', 'normScore', 'margin', ...
    'accepted', 'correct', 'nQueryHashes', 'nCandidateSongs', 'snrDbMeasured', ...
    'warmup', 'tHashSec', 'tMatchSec', 'tTotalSec'});

% ---- Provenance (blueprint 6.4) -----------------------------------------
R.Properties.UserData = struct( ...
    'system',      string(systemName), ...
    'cfg',         Cfg, ...
    'cfgTag',      Cfg.tag, ...
    'indexTag',    Idx.cfgTag, ...
    'matlabVer',   version('-release'), ...
    'gitCommit',   gitCommit(), ...
    'runOn',       datetime('now'), ...
    'elapsedSec',  elapsed, ...
    'usedParfor',  opt.UseParfor, ...
    'warmupN',     opt.WarmupN, ...
    'timingValid', ~opt.UseParfor);

logMsg('info', 'runExperiment: %s complete in %.1f s (%.1f min).', ...
    systemName, elapsed, elapsed / 60);

if opt.UseParfor
    logMsg('warn', ...
        'runExperiment ran under parfor - do NOT quote tMatchSec from this run (blueprint 6.3).');
end

end

% =======================================================================
function [p1, s1, p2, s2, ns, mg, acc, nqh, ncs, snrMeas, tHash, tMatch, tTot] = ...
    runOne(row, catalog, Idx, Cfg, cache)

[y, meas] = synthesizeQuery(row, catalog, Cfg, cache);

tStart = tic;
res    = identifyQuery(y, Idx, Cfg);
tTot   = toc(tStart);

p1  = uint16(res.pred1);
s1  = res.score1;
p2  = uint16(res.pred2);
s2  = res.score2;
ns  = res.normScore;
mg  = res.margin;
acc = logical(res.accepted);
nqh = res.nQueryHashes;
ncs = res.nCandidateSongs;
snrMeas = meas.snrDbMeasured;
tHash   = res.tHashSec;
tMatch  = res.tMatchSec;

end

% =======================================================================
function h = gitCommit()
%GITCOMMIT Short commit hash, or "unknown" outside a repo (blueprint 6.4).
h = "unknown";
try
    old = cd(setupPaths());
    c   = onCleanup(@() cd(old));
    [st, out] = system('git rev-parse --short HEAD');
    if st == 0
        h = string(strtrim(out));
    end
catch
    % Leave "unknown" - provenance is best effort, never a reason to abort a
    % three-hour run.
end
end
