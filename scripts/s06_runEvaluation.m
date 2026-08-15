%S06_RUNEVALUATION  Run the query grid against an index and write results.
%
%   Reads results/queryManifest.csv, runs every query through IDENTIFYQUERY,
%   and writes results/raw/results_<system>_<timestamp>.csv plus a .mat
%   carrying the full provenance blueprint 6.4 requires.
%
%   Configure with variables set BEFORE running the script (all optional):
%
%       s06_system   'baseline' (default)
%       s06_subset   number of songs to sample, or [] for all (default [])
%       s06_split    'dev' | 'test' | 'all'   (default 'all')
%       s06_parfor   true | false             (default false)
%
%   For example, the M3 end-to-end validation blueprint 7 asks for:
%
%       s06_subset = 20;  s06_runEvaluation
%
%   then the full run with the variable cleared.
%
%   RUN THE SUBSET FIRST. It is 20/120 of the grid and it exercises every
%   path the full run does. A manifest error, a missing noise file or a
%   threshold mistake costs minutes there and hours in the full run.
%
%   THE SPLIT ARGUMENT IS A SAFETY RAIL, NOT A CONVENIENCE. Blueprint 8.2:
%   the test split is touched exactly once, at M7. Every sweep before then -
%   alpha, beta, kappaDb, tau, rho, freqDecim - runs on dev. Passing
%   'dev' here makes that explicit in the results file rather than something
%   a reader has to reconstruct from which rows are present.
%
%   TIMING AND PARFOR DO NOT MIX. parfor is the right way to run the grid for
%   accuracy (8.1) and the wrong way to measure latency: workers contend and
%   the per-query times cannot support success criterion 3. The results file
%   records which was used, and RUNEXPERIMENT warns.
%
%   Milestone: M3 (baseline validation), M7 (full factorial, both systems).
%   Blueprint: sections 2.6, 6.3, 6.4, 8.1, 8.2, 8.3.
%
%   Usage:
%       setupPaths;
%       s06_subset = 20;
%       s06_runEvaluation

projRoot = setupPaths();
Cfg      = baselineConfig();
rng(Cfg.seed, 'twister');

if ~exist('s06_system', 'var') || isempty(s06_system), s06_system = 'baseline'; end
if ~exist('s06_subset', 'var'),                        s06_subset = [];         end
if ~exist('s06_split',  'var') || isempty(s06_split),  s06_split  = 'all';      end
if ~exist('s06_parfor', 'var') || isempty(s06_parfor), s06_parfor = false;      end

logMsg('info', '===== s06_runEvaluation =====');
logMsg('info', 'MATLAB %s | system %s | config tag %s', ...
    version('-release'), s06_system, Cfg.tag);

problems = strings(0, 1);

% =======================================================================
% 1. Index
% =======================================================================
indexPath = fullfile(projRoot, 'db', sprintf('index_%s.mat', Cfg.tag));
if ~isfile(indexPath)
    error('HimigTransform:NoIndex', ...
        'No index at %s.\nRun s03_enroll first.', indexPath);
end

S   = load(indexPath, 'Idx');
Idx = S.Idx;

% The index and the config must be the same config. This is the check that
% would have caught the 21x21 cache being reused under a 17x17 Cfg: the
% artifact carried a tag it did not match, and nothing downstream noticed
% until the numbers were already in a table.
if ~strcmp(Idx.cfgTag, Cfg.tag)
    error('HimigTransform:IndexConfigMismatch', ...
        ['Index was built under tag "%s" but baselineConfig resolves to "%s". ' ...
         'Re-run s03_enroll.'], Idx.cfgTag, Cfg.tag);
end

logMsg('info', 'Index: %d song(s), %d postings, %d distinct keys.', ...
    Idx.stats.nSongsEnrolled, Idx.stats.nHashes, Idx.stats.nDistinct);

% =======================================================================
% 2. Manifest, filtered
% =======================================================================
catalog = loadCatalog(Cfg);
M       = loadQueryManifest(Cfg);

nFull = height(M);

if ~strcmpi(s06_split, 'all')
    M = M(M.split == s06_split, :);
    logMsg('info', 'Split filter: %s (%d of %d rows).', s06_split, height(M), nFull);
end

if ~isempty(s06_subset)
    % Sample SONGS, not rows. Taking the first N rows would give a handful of
    % songs at every condition; taking N songs keeps the grid shape intact so
    % the validation run actually exercises the full condition set.
    songs = unique(M.songID);
    stream = RandStream('twister', 'Seed', Cfg.seed);
    keep   = songs(randperm(stream, numel(songs), min(s06_subset, numel(songs))));
    M      = M(ismember(M.songID, keep), :);
    logMsg('info', 'Subset: %d song(s), %d quer(ies).', numel(keep), height(M));
end

if isempty(M)
    error('HimigTransform:EmptyManifestAfterFilter', ...
        'No queries left after filtering by split "%s" and subset %s.', ...
        s06_split, mat2str(s06_subset));
end

% =======================================================================
% 3. Run
% =======================================================================
R = runExperiment(M, Idx, Cfg, s06_system, ...
    'Catalog', catalog, 'UseParfor', s06_parfor);

% =======================================================================
% 4. Write
% =======================================================================
stamp   = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
rawDir  = fullfile(projRoot, 'results', 'raw');
baseName = sprintf('results_%s_%s', s06_system, stamp);

csvPath = fullfile(rawDir, [baseName '.csv']);
matPath = fullfile(rawDir, [baseName '.mat']);

writetable(R, csvPath);
save(matPath, 'R', 'Cfg', '-v7.3');

logMsg('info', 'Results written to %s', csvPath);

% =======================================================================
% 5. Headline metrics
% =======================================================================
T = computeMetrics(R, {'lengthSec', 'targetSnrDb'});

tablePath = fullfile(projRoot, 'results', 'tables', ...
    sprintf('metrics_%s_%s.csv', s06_system, stamp));
writetable(T, tablePath);

fprintf('\n--- Closed-set top-1 accuracy, %% (Wilson 95%%) ---\n');
fprintf('  %8s', 'SNR');
lengths = unique(T.lengthSec);
for L = lengths', fprintf(' %18s', sprintf('%g s', L)); end
fprintf('\n');

snrOrder = [Inf; sort(unique(T.targetSnrDb(~isinf(T.targetSnrDb))), 'descend')];
for s = snrOrder'
    if isinf(s), fprintf('  %8s', 'clean'); else, fprintf('  %8g', s); end
    for L = lengths'
        if isinf(s)
            sel = T.lengthSec == L & isinf(T.targetSnrDb);
        else
            sel = T.lengthSec == L & T.targetSnrDb == s;
        end
        row = T(sel, :);
        if isempty(row)
            fprintf(' %18s', '-');
        else
            fprintf(' %8.1f [%4.1f-%4.1f]', 100 * row.closedSetAcc(1), ...
                100 * row.closedSetAccLo(1), 100 * row.closedSetAccHi(1));
        end
    end
    fprintf('\n');
end

fprintf('\n  n per cell: %d - %d in-DB quer(ies)\n', min(T.nInDb), max(T.nInDb));

% =======================================================================
% 5b. Headroom - can success criterion 1 be demonstrated, and where?
% =======================================================================
% Criterion 1 asks for a >= 10 pp accuracy gain over the baseline. A gain
% that large is only possible where the baseline has left at least 10 pp on
% the table. On a 100-song database the baseline saturates well past 0 dB, so
% this block says plainly which cells can carry the claim.
%
% Headroom is necessary, not sufficient: at the bottom of the curve both
% systems approach zero and there is nothing left to recover either. The
% usable region is the steep middle.
fprintf('\n--- Headroom for the enhanced system (100%% - baseline) ---\n');
fprintf('%8s', 'SNR');
fprintf('%10.0f s', Cfg.eval.lengthsSec);
fprintf('   %s\n', 'usable?');

snrList = unique(T.targetSnrDb, 'stable');
for si = 1:numel(snrList)
    snr = snrList(si);
    if isinf(snr) && snr > 0
        fprintf('%8s', 'clean');
    else
        fprintf('%8.0f', snr);
    end

    room = nan(1, numel(Cfg.eval.lengthsSec));
    for li = 1:numel(Cfg.eval.lengthsSec)
        m = T.targetSnrDb == snr & T.lengthSec == Cfg.eval.lengthsSec(li);
        if any(m)
            room(li) = 100 * (1 - T.closedSetAcc(find(m, 1)));
        end
        fprintf('%10.1f  ', room(li));
    end

    nUsable = nnz(room >= 10);
    if nUsable == 0
        note = 'saturated - no 10 pp gain is possible here';
    elseif all(room(~isnan(room)) > 80)
        note = 'floor - both systems near zero, gain unlikely';
    elseif nUsable == numel(room)
        note = 'USABLE at every length';
    else
        note = 'usable at the shorter lengths only';
    end
    fprintf(' %s\n', note);
end

fprintf(['\n  Report the proposal''s clean/10/5/0 row as measured - a\n' ...
         '  saturated baseline on a 100-song database is a real result. Then\n' ...
         '  demonstrate the recovery where the baseline actually degrades,\n' ...
         '  and say in the paper which SNR carries the criterion-1 claim.\n']);

% Open-set numbers are plumbing until tau and rho are calibrated on dev at M5.
% Printing them without that caveat is how a placeholder threshold ends up
% quoted as a result.
%
% POOLED OPEN-SET FIGURES ARE NOT A PROPERTY OF THE SYSTEM. Recall and FAR
% pooled over the whole grid depend on the grid's COMPOSITION: every SNR point
% added below the knee drags pooled recall down, and every one added above it
% pushes recall up, without a line of code changing. Extending the grid to
% -25 dB is what moved pooled recall from ~1.0 to ~0.6, not any change in
% behaviour. The same applies to FAR: a holdout query at -25 dB generates
% almost no usable hashes, so it is rejected for the wrong reason and flatters
% the number.
%
% Quote open-set metrics AT A NAMED CONDITION, never pooled.
fprintf('\n--- Open-set (tau = %.3f, rho = %.2f - PLACEHOLDERS, tuned at M5) ---\n', ...
    Cfg.match.tau, Cfg.match.rho);

Topen = computeMetrics(R, {'lengthSec', 'targetSnrDb'});

fprintf('%8s %8s %11s %9s %8s %8s\n', ...
    'length', 'SNR', 'precision', 'recall', 'FAR', 'n(hold)');
for li = 1:numel(Cfg.eval.lengthsSec)
    for si = 1:numel(snrList)
        m = Topen.lengthSec == Cfg.eval.lengthsSec(li) & ...
            Topen.targetSnrDb == snrList(si);
        if ~any(m), continue, end
        r = find(m, 1);

        if isinf(snrList(si)) && snrList(si) > 0
            snrLabel = 'clean';
        else
            snrLabel = sprintf('%.0f', snrList(si));
        end

        fprintf('%7.0fs %8s %11.3f %9.3f %8.3f %8d\n', ...
            Cfg.eval.lengthsSec(li), snrLabel, ...
            Topen.precision(r), Topen.recall(r), Topen.far(r), Topen.nHoldout(r));
    end
end

Tall = computeMetrics(R, {'system'});
fprintf('\n  pooled over the WHOLE grid: precision %.3f, recall %.3f, FAR %.3f\n', ...
    Tall.precision, Tall.recall, Tall.far);
fprintf('  ^ grid-composition artefact. Do not quote it; quote a row above.\n');
fprintf('  All of these are a plumbing check until tau/rho are tuned at M5.\n');

% =======================================================================
% 6. Timing (blueprint 6.3)
% =======================================================================
warm = ~R.warmup;
fprintf('\n--- Match time (warm-up %d discarded, index load excluded) ---\n', nnz(R.warmup));
fprintf('  median : %.4f s\n', median(R.tMatchSec(warm)));
fprintf('  p95    : %.4f s\n', prctile95(R.tMatchSec(warm)));
fprintf('  total median (hash + match) : %.4f s\n', median(R.tTotalSec(warm)));

if s06_parfor
    fprintf('  NOT VALID for criterion 3 - this run used parfor.\n');
elseif median(R.tTotalSec(warm)) >= 1.0
    problems(end + 1) = sprintf('median total match time %.3f s exceeds the 1 s criterion', ...
        median(R.tTotalSec(warm))); %#ok<SAGROW>
end

% =======================================================================
% 7. Exit check
% =======================================================================
inDb = R.isInDb;
clean10 = inDb & isinf(R.targetSnrDb) & R.lengthSec == max(Cfg.eval.lengthsSec);

fprintf('\n--- s06 exit check ---\n');
fprintf('System                  : %s\n',      s06_system);
fprintf('Queries run             : %d\n',      height(R));
fprintf('Clean %gs top-1          : %.1f%% (n = %d)\n', ...
    max(Cfg.eval.lengthsSec), 100 * mean(R.correct(clean10)), nnz(clean10));
fprintf('Overall in-DB top-1     : %.1f%%\n',  100 * mean(R.correct(inDb)));
fprintf('Results                 : %s\n',      csvPath);

if nnz(clean10) > 0 && mean(R.correct(clean10)) < 0.95
    problems(end + 1) = sprintf('clean %gs top-1 is %.1f%%, below the 95%% M2 gate', ...
        max(Cfg.eval.lengthsSec), 100 * mean(R.correct(clean10))); %#ok<SAGROW>
end

if isempty(problems)
    fprintf('s06_runEvaluation: PASS\n');
    if ~isempty(s06_subset)
        fprintf('Subset validated. Clear s06_subset and re-run for the full grid.\n');
    else
        fprintf('Next: s07_makeFigures, then git tag v0.1-baseline-frozen.\n');
    end
else
    fprintf('s06_runEvaluation: BLOCKED\n');
    for k = 1:numel(problems)
        fprintf('  - %s\n', problems(k));
    end
end
fprintf('---------------------\n');

% =======================================================================
function v = prctile95(x)
x = sort(x(:));
n = numel(x);
if n == 0, v = NaN; return; end
if n == 1, v = x;   return; end
pos = min(max(0.95 * n + 0.5, 1), n);
lo  = floor(pos); hi = ceil(pos);
if lo == hi, v = x(lo); else, v = x(lo) + (pos - lo) * (x(hi) - x(lo)); end
end