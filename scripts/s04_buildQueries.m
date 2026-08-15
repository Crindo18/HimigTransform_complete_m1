%S04_BUILDQUERIES  Build and verify the evaluation query manifest (D2).
%
%   Writes results/queryManifest.csv and .mat, exports a small set of real
%   WAVs for the GUI demo and report figures, and checks the invariants the
%   statistics in blueprint 8.4 depend on before anything downstream trusts
%   the table.
%
%   NO QUERY WAVS. Blueprint D2: the full factorial is ~1 GB of audio that
%   cannot go in Git and drifts between group members. The manifest plus
%   SYNTHESIZEQUERY regenerates every waveform on demand, bit for bit. The
%   ~30 exported WAVs are for the demo and for figures only - nothing in the
%   evaluation path reads them.
%
%   THE CHECKS AT THE END ARE NOT CEREMONY. Every one of them corresponds to
%   a statistic that becomes indefensible if it fails, and none is visible by
%   eye in a 17,000-row table. They duplicate what tQueryManifest asserts, on
%   purpose: the test proves the code is right on whatever data the suite can
%   reach, this proves the artifact on disk is right for the corpus actually
%   being used.
%
%   Idempotent. Deterministic from Cfg.seed, so a re-run overwrites the same
%   table row for row.
%
%   Milestone: M3.  Blueprint: sections 0 (D2), 2.5, 8.1, 8.2, 8.4, 9 (R10).
%
%   Usage:
%       setupPaths;
%       s04_buildQueries

projRoot = setupPaths();
Cfg      = baselineConfig();
rng(Cfg.seed, 'twister');

logMsg('info', '===== s04_buildQueries =====');
logMsg('info', 'MATLAB %s | config tag %s', version('-release'), Cfg.tag);

catalog  = loadCatalog(Cfg);
problems = strings(0, 1);

% =======================================================================
% 1. Build
% =======================================================================
M = buildQueryManifest(catalog, Cfg);

manifestCsv = fullfile(projRoot, 'results', 'queryManifest.csv');
manifestMat = fullfile(projRoot, 'results', 'queryManifest.mat');

writetable(M, manifestCsv);
save(manifestMat, 'M', 'Cfg', '-v7.3');

logMsg('info', 'Manifest written to %s', manifestCsv);

% =======================================================================
% 2. Grid shape
% =======================================================================
snrFinite   = Cfg.eval.snrDb(~isinf(Cfg.eval.snrDb));
nPerExcerpt = 1 + numel(Cfg.eval.noiseTypes) * numel(snrFinite);
expected    = height(catalog) * numel(Cfg.eval.lengthsSec) * ...
              Cfg.eval.repsPerSong * nPerExcerpt;

fprintf('\n--- Query grid ---\n');
fprintf('  songs               : %d (%d in-DB, %d holdout)\n', ...
    height(catalog), nnz(catalog.role == 'db'), nnz(catalog.role == 'holdout'));
fprintf('  lengths             : %s s\n', num2str(Cfg.eval.lengthsSec));
fprintf('  reps per song       : %d\n', Cfg.eval.repsPerSong);
fprintf('  SNR grid            : %s dB\n', num2str(Cfg.eval.snrDb));
fprintf('  noise types         : %s\n', strjoin(cellstr(string(Cfg.eval.noiseTypes)), ', '));
fprintf('  conditions/excerpt  : %d (1 clean + %d x %d)\n', ...
    nPerExcerpt, numel(Cfg.eval.noiseTypes), numel(snrFinite));
fprintf('  queries per system  : %d\n', height(M));

if height(M) ~= expected
    problems(end + 1) = sprintf('manifest has %d rows, expected %d', height(M), expected); %#ok<SAGROW>
end

% =======================================================================
% 3. Invariants
% =======================================================================
fprintf('\n--- Invariants ---\n');

% (a) One excerpt per (song, length, rep), shared across every condition.
%     This is what pairs baseline against enhanced and licenses McNemar (8.4).
Ga = findgroups(M.songID, M.lengthSec, M.rep);
na = splitapply(@(s) numel(unique(s)), M.startSample, Ga);
okA = all(na == 1);
fprintf('  excerpt shared across conditions : %s (%d group(s))\n', passFail(okA), numel(na));
if ~okA
    problems(end + 1) = "startSample varies within a (song, length, rep) group"; %#ok<SAGROW>
end

% (b) One noise segment per (song, length, rep, noiseType), shared across SNR.
%     Without this the SNR axis mixes 'less favourable SNR' with 'different
%     babble' and stops isolating the variable it is plotted against.
noisy = M(M.noiseType ~= 'none', :);
Gb = findgroups(noisy.songID, noisy.lengthSec, noisy.rep, noisy.noiseType);
nb = splitapply(@(s) numel(unique(s)), noisy.noiseStartSample, Gb);
okB = all(nb == 1);
fprintf('  noise segment shared across SNR  : %s (%d group(s))\n', passFail(okB), numel(nb));
if ~okB
    problems(end + 1) = "noiseStartSample varies across SNR; the SNR axis is confounded"; %#ok<SAGROW>
end

% Song-level split (8.2). A song in both dev and test is the leak that makes
% every tuned threshold indefensible at the panel.
Gc = findgroups(M.songID);
nc = splitapply(@(s) numel(unique(s)), string(M.split), Gc);
okC = all(nc == 1);
fprintf('  split assigned at song level     : %s\n', passFail(okC));
if ~okC
    problems(end + 1) = "a songID appears under more than one split"; %#ok<SAGROW>
end

% Holdout songs must be queried - they are the open-set negatives (8.3).
nHoldCat = numel(unique(catalog.songID(catalog.role == 'holdout')));
nHoldQ   = numel(unique(M.songID(M.role == 'holdout')));
okD      = nHoldQ == nHoldCat;
fprintf('  holdout songs queried            : %s (%d of %d)\n', passFail(okD), nHoldQ, nHoldCat);
if ~okD
    problems(end + 1) = sprintf('only %d of %d holdout songs appear in the manifest', ...
        nHoldQ, nHoldCat); %#ok<SAGROW>
end

okE = numel(unique(M.queryID)) == height(M);
fprintf('  queryID unique                   : %s\n', passFail(okE));
if ~okE
    problems(end + 1) = "queryID is not unique"; %#ok<SAGROW>
end

% =======================================================================
% 4. Noise coverage
% =======================================================================
% An earlier version drew the offset with randi(8000*10), capping it at the
% first 10 s of a 300 s recording - so every query of a given type heard
% nearly the same babble and 97% of the bank went unused.
bank = loadNoiseBank(Cfg);

fprintf('\n--- Noise bank coverage ---\n');
fprintf('  %-10s %10s %12s %10s\n', 'type', 'file(s)', 'span used', 'queries');
okF = true;
for k = 1:height(bank)
    sel = noisy(noisy.noiseType == bank.noiseType(k), :);
    if isempty(sel), continue; end
    spanFrac = double(max(sel.noiseStartSample)) / double(bank.nSamples(k));
    fprintf('  %-10s %10s %11.0f%% %10d\n', ...
        char(bank.noiseType(k)), char(bank.file(k)), 100 * spanFrac, height(sel));
    if spanFrac < 0.25
        okF = false;
    end
end
if ~okF
    problems(end + 1) = "noise offsets cover less than a quarter of the bank"; %#ok<SAGROW>
end

% Every referenced file must exist, or every noisy query fails at run time.
refFiles = unique(noisy.noiseFile);
missingNoise = strings(0, 1);
for k = 1:numel(refFiles)
    f = fullfile(projRoot, 'data', 'noise', char(refFiles(k)));
    if ~isfile(f)
        missingNoise(end + 1) = string(f); %#ok<SAGROW>
    end
end
if isempty(missingNoise)
    fprintf('  all referenced noise files exist : PASS\n');
else
    fprintf('  all referenced noise files exist : FAIL\n');
    for k = 1:numel(missingNoise)
        fprintf('    missing: %s\n', missingNoise(k));
    end
    problems(end + 1) = sprintf('%d referenced noise file(s) do not exist', ...
        numel(missingNoise)); %#ok<SAGROW>
end

% =======================================================================
% 5. Synthesis spot check
% =======================================================================
% One row per distinct SNR, regenerated for real. This is where a path bug,
% a wrong filename or a mixer fault surfaces - and it costs a few seconds
% against a grid that costs hours.
fprintf('\n--- Synthesis spot check ---\n');

snrList  = unique(M.targetSnrDb);
worstErr = 0;
cache    = containers.Map('KeyType', 'char', 'ValueType', 'any');

for k = 1:numel(snrList)
    idx = find(M.targetSnrDb == snrList(k), 1);
    row = M(idx, :);

    try
        [y, meas] = synthesizeQuery(row, catalog, Cfg, cache);
    catch ME
        fprintf('  %8s dB : ERROR - %s\n', snrLabel(snrList(k)), ME.message);
        problems(end + 1) = sprintf('synthesis failed at %s dB: %s', ...
            snrLabel(snrList(k)), ME.message); %#ok<SAGROW>
        continue
    end

    wantLen = round(row.lengthSec * Cfg.audio.fs);
    lenOk   = numel(y) == wantLen;
    peak    = max(abs(y));

    if isinf(snrList(k))
        errDb = 0;
        fprintf('  %8s    : len %d %s, peak %.3f\n', ...
            snrLabel(snrList(k)), numel(y), passFail(lenOk), peak);
    else
        errDb = abs(meas.snrDbMeasured - row.targetSnrDb);
        fprintf('  %8s dB : len %d %s, peak %.3f, measured %.3f dB (err %.4f)\n', ...
            snrLabel(snrList(k)), numel(y), passFail(lenOk), peak, ...
            meas.snrDbMeasured, errDb);
    end

    worstErr = max(worstErr, errDb);

    if ~lenOk
        problems(end + 1) = sprintf('query at %s dB is %d samples, expected %d', ...
            snrLabel(snrList(k)), numel(y), wantLen); %#ok<SAGROW>
    end
    if peak > 1.0
        problems(end + 1) = sprintf('query at %s dB clips (peak %.3f)', ...
            snrLabel(snrList(k)), peak); %#ok<SAGROW>
    end
end

if worstErr > 0.1
    problems(end + 1) = sprintf('measured SNR off target by %.3f dB (contract is 0.1)', ...
        worstErr); %#ok<SAGROW>
end

% Bit-exact regeneration is the entire basis of D2: no WAVs are stored, so if
% the same row does not reproduce the same samples, two group members are
% comparing different audio and nothing says so.
probe = M(find(~isinf(M.targetSnrDb), 1), :);
y1 = synthesizeQuery(probe, catalog, Cfg);
y2 = synthesizeQuery(probe, catalog, Cfg);
okG = isequal(y1, y2);
fprintf('  bit-exact on regeneration : %s\n', passFail(okG));
if ~okG
    problems(end + 1) = "regeneration is not bit-exact; D2 does not hold"; %#ok<SAGROW>
end

% =======================================================================
% 6. Demo WAVs (blueprint D2: ~30, for the GUI and figures only)
% =======================================================================
demoDir = fullfile(projRoot, 'data', 'demoQueries');
if ~isfolder(demoDir)
    mkdir(demoDir);
end

% A spread across repertoire, length and condition rather than the first 30
% rows, so the demo set cannot be all-American, all-clean, all-10 s.
demoRows = pickDemoRows(M, 30);
nWritten = 0;

for k = 1:numel(demoRows)
    row = M(demoRows(k), :);
    try
        y = synthesizeQuery(row, catalog, Cfg, cache);
    catch
        continue
    end
    name = sprintf('q%05d_song%03d_%gs_%s_%sdB.wav', ...
        double(row.queryID), double(row.songID), row.lengthSec, ...
        char(row.noiseType), snrLabel(row.targetSnrDb));
    audiowrite(fullfile(demoDir, name), y, Cfg.audio.fs);
    nWritten = nWritten + 1;
end

fprintf('\n--- Demo WAVs ---\n');
fprintf('  %d file(s) written to %s\n', nWritten, demoDir);
fprintf('  (GUI and figures only - the evaluation path never reads these)\n');

% =======================================================================
% 7. Exit check
% =======================================================================
fprintf('\n--- s04 exit check ---\n');
fprintf('Queries per system      : %d\n',   height(M));
fprintf('In-DB / holdout rows    : %d / %d\n', nnz(M.role == 'db'), nnz(M.role == 'holdout'));
fprintf('Worst SNR error         : %.4f dB\n', worstErr);
fprintf('Manifest                : %s\n',   manifestCsv);

if isempty(problems)
    fprintf('s04_buildQueries: PASS\n');
    fprintf('Next: s06_runEvaluation with ''Subset'', 20 to validate end to end,\n');
    fprintf('then the full run, then s07_makeFigures, THEN tag v0.1-baseline-frozen.\n');
else
    fprintf('s04_buildQueries: BLOCKED\n');
    for k = 1:numel(problems)
        fprintf('  - %s\n', problems(k));
    end
end
fprintf('---------------------\n');

% =======================================================================
function s = passFail(tf)
if tf, s = 'PASS'; else, s = 'FAIL'; end
end

function s = snrLabel(v)
if isinf(v), s = 'clean'; else, s = sprintf('%g', v); end
end

function idx = pickDemoRows(M, n)
%PICKDEMOROWS Spread the demo set across repertoire, length and condition.
key = findgroups(M.repertoire, M.lengthSec, M.noiseType);
idx = zeros(0, 1);
g   = 1;
while numel(idx) < n && g <= max(key)
    hits = find(key == g);
    if ~isempty(hits)
        idx(end + 1) = hits(1); %#ok<AGROW>
    end
    g = g + 1;
end
idx = idx(1:min(n, numel(idx)));
end