%S03B_SWEEPPEAKNBHD  Choose the peak neighbourhood before M3 freezes the baseline.
%
%   Sweeps Cfg.peaks.nbhdF/nbhdT over a few odd sizes and reports, for each,
%   the achieved peak density, whether the density cap actually binds, index
%   size, enrolment time and clean 10 s top-1 accuracy.
%
%   WHY THIS SCRIPT EXISTS. At the current 21x21 neighbourhood the geometric
%   ceiling is 18.2 peaks/s, below the configured target of 25, so
%   Cfg.peaks.densityPerSec never binds and measured density (12.1/s) is set
%   entirely by the neighbourhood. Blueprint 3.3 caps density per second and
%   per band for two reasons - so a long track cannot dominate the index, and
%   so the bass region cannot swallow the budget - and neither guarantee holds
%   while the cap is inert.
%
%   The consequence that matters is at M4. Both peak pickers run through
%   ENFORCEPEAKDENSITY specifically so fixed and adaptive are compared at
%   EQUAL PEAK BUDGET. If the cap never binds, the adaptive picker can win by
%   emitting more peaks - the exact confound the design exists to remove.
%
%   MEASURE, DO NOT GUESS. A smaller neighbourhood raises density but admits
%   weaker, closely spaced maxima, and those are the first thing noise
%   destroys - which is precisely the robustness this project is built to
%   measure. Clean accuracy alone will not show that cost; it will look flat
%   or improve. Treat this sweep as choosing the largest neighbourhood that
%   lets the cap bind, not the one with the best clean number.
%
%   RUN THIS BEFORE `git tag v0.1-baseline-frozen`. It rebuilds one index per
%   setting, so it costs roughly (number of settings x 15 s) plus accuracy
%   checks - about ten minutes for four settings on the 100-song corpus. It
%   is the last cheap moment to make this choice.
%
%   Writes results/tables/peakNbhdSweep.csv. Changes nothing else: the
%   configuration is only edited in memory, and the indexes it builds carry
%   their own config tags so they cannot be confused with the baseline.
%
%   Milestone: M2/M3 boundary.  Blueprint: sections 3.3, 7 (M3).
%
%   See also PEAKBUDGETAUDIT, ENFORCEPEAKDENSITY, S03_ENROLL.

projRoot = setupPaths();

Cfg = baselineConfig();
rng(Cfg.seed, 'twister');

logMsg('info', '===== s03b_sweepPeakNbhd =====');

nbhdList = [21 19 17 15 13];
nAccuracyCheck = 25;      % songs sampled for the accuracy probe; raise for the
                          % final number, this is for choosing between settings

catalog = loadCatalog(Cfg);
dbRows  = catalog(catalog.role == 'db', :);
songIDs = double(dbRows.songID);

if isempty(songIDs)
    error('HimigTransform:NoCatalog', ...
        'No enrolled songs in the catalog. Run s01_ingest first.');
end

rows = cell(numel(nbhdList), 1);

for ii = 1:numel(nbhdList)
    r = nbhdList(ii);

    Sweep = Cfg;
    Sweep.peaks.nbhdF = r;
    Sweep.peaks.nbhdT = r;
    Sweep.name        = sprintf('sweep%02d', r);
    Sweep.tag         = makeConfigTag(Sweep);

    audit = peakBudgetAudit(Sweep);

    fprintf('\n===== neighbourhood %dx%d =====\n', r, r);
    fprintf('  ceiling %.1f/s vs target %d/s -> cap %s bind\n', ...
        audit.ceilingPerSec, Sweep.peaks.densityPerSec, ...
        ternary(audit.capCanBind, 'CAN', 'CANNOT'));

    [Idx, report] = enrollDatabase(catalog, Sweep);

    ok   = report.action ~= "failed";
    dens = report.densityPerSec(ok);

    % Accuracy probe on a subset - enough to separate the settings, not the
    % final headline number.
    probeIDs = songIDs(round(linspace(1, numel(songIDs), ...
        min(nAccuracyCheck, numel(songIDs)))));

    nCorrect = 0;
    tMatch   = zeros(numel(probeIDs), 1);

    for k = 1:numel(probeIDs)
        id = probeIDs(k);
        relPath = char(catalog.procPath(catalog.songID == id));
        f = fullfile(projRoot, 'data', 'processed', strrep(relPath, '/', filesep));

        x = audioread(f);
        lenSamp = min(10 * Sweep.audio.fs, numel(x));
        start = max(1, floor(numel(x) / 3));
        q = x(start : min(start + lenSamp - 1, numel(x)));

        res = identifyQuery(q, Idx, Sweep);
        nCorrect = nCorrect + (res.pred1 == id);
        tMatch(k) = res.tTotalSec;
    end

    acc = nCorrect / numel(probeIDs);

    rows{ii} = struct( ...
        'nbhd',            r, ...
        'ceilingPerSec',   audit.ceilingPerSec, ...
        'capCanBind',      audit.capCanBind, ...
        'densityMean',     mean(dens), ...
        'densityMedian',   median(dens), ...
        'nPostings',       Idx.stats.nHashes, ...
        'nDistinctKeys',   Idx.stats.nDistinct, ...
        'megabytes',       Idx.stats.bytes / 2^20, ...
        'enrolSec',        Idx.stats.enrolSec, ...
        'clean10sTop1',    acc, ...
        'medMatchSec',     median(tMatch));

    fprintf('  density %.1f/s | %d postings | %.1f MB | top-1 %.1f%% (n=%d)\n', ...
        mean(dens), Idx.stats.nHashes, Idx.stats.bytes / 2^20, ...
        100 * acc, numel(probeIDs));

    clear Idx
end

% ---- Table --------------------------------------------------------------
T = struct2table([rows{:}]);

fprintf('\n');
fprintf('=================== peak neighbourhood sweep ===================\n');
fprintf('%6s %10s %8s %10s %11s %8s %9s\n', ...
    'nbhd', 'ceiling/s', 'binds', 'density/s', 'postings', 'MB', 'top-1');
for ii = 1:height(T)
    fprintf('%4dx%-2d %9.1f %8s %10.1f %11d %8.1f %8.1f%%\n', ...
        T.nbhd(ii), T.nbhd(ii), T.ceilingPerSec(ii), ...
        ternary(T.capCanBind(ii), 'yes', 'NO'), ...
        T.densityMean(ii), T.nPostings(ii), T.megabytes(ii), ...
        100 * T.clean10sTop1(ii));
end
fprintf('===============================================================\n');

outDir = fullfile(projRoot, 'results', 'tables');
if ~isfolder(outDir)
    mkdir(outDir);
end
outPath = fullfile(outDir, 'peakNbhdSweep.csv');
writetable(T, outPath);

fprintf('\nWritten to %s\n', outPath);
fprintf(['\nHOW TO READ THIS. Pick the LARGEST neighbourhood whose cap binds,\n' ...
         'not the best clean accuracy - clean queries will not reveal the\n' ...
         'noise cost of admitting weaker, closely spaced peaks, and that cost\n' ...
         'lands on exactly the 0 dB and 3 s cases the enhancements target.\n' ...
         'Record the choice in docs/designNotes.md, update baselineConfig and\n' ...
         'tPeakBudget, re-run s03_enroll, THEN tag v0.1-baseline-frozen.\n']);

% =======================================================================
function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
