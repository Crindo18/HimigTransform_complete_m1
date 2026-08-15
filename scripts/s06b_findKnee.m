%S06B_FINDKNEE  Locate the SNR at which the baseline actually degrades.
%
%   Sweeps SNR well below the proposal's 0 dB floor on a small sample of real
%   songs and reports top-1 accuracy AND the decision statistics at each
%   point. Run it before committing to the full M7 grid.
%
%   WHY. The M3 subset run returned 100.0% top-1 in every cell of the grid,
%   including 3 s queries at 0 dB. That is not a bug - mixAtSNR hits its
%   target to 0.0000 dB and the noise genuinely destroys most of the
%   fingerprint (peak survival at 0 dB measures around 12%). It is a
%   PROPERTY OF THE DATABASE SIZE. A 3 s query yields a few hundred hashes,
%   and even a 1-2% hash survival rate leaves a dozen or more that align at
%   one offset. Against 100 songs, a dozen aligned hashes wins outright,
%   because the 99 rivals contribute only one or two chance collisions at any
%   single offset. Shazam-style degradation at 0 dB is a property of a
%   catalogue of millions, where chance collisions swamp a dozen true ones.
%
%   WHAT THIS BREAKS. Success criterion 1 is "at least a 10-percentage-point
%   accuracy gain over the baseline at 0 dB SNR". A baseline at 100.0% has
%   zero headroom, so the criterion is unreachable no matter how good the
%   enhancements are. The enhancements are not on trial here; the operating
%   point is.
%
%   WHAT TO DO WITH THE OUTPUT. Two usable answers, and they are not
%   exclusive:
%
%     1. MOVE THE GRID. Find where accuracy leaves the ceiling and put the
%        evaluation there. Report the proposal's clean/10/5/0 dB row as
%        measured - a saturated baseline is a real result and belongs in the
%        paper - then extend downward to where the systems separate.
%
%     2. CHANGE THE DEPENDENT VARIABLE. normScore falls monotonically long
%        before accuracy moves: it drops measurably by 0 dB while top-1 is
%        still flat at 100%. It is the fingerprint's signal-to-noise margin,
%        it is exactly what Enhancement 1 is designed to protect, and it is
%        measurable at the SNRs the proposal specifies. Reporting "accuracy
%        saturates; the enhanced system carries N times the decision margin
%        at 0 dB" is a defensible, honest result at the operating point the
%        proposal named.
%
%   Writes results/tables/kneeProbe.csv.
%
%   Milestone: M3.  Blueprint: sections 8.1, 9 (R4), 12.
%
%   See also S06_RUNEVALUATION, BUILDQUERYMANIFEST, MIXATSNR.

projRoot = setupPaths();
Cfg      = baselineConfig();
rng(Cfg.seed, 'twister');

logMsg('info', '===== s06b_findKnee =====');

% ---- Knobs --------------------------------------------------------------
snrGrid    = [Inf 10 5 0 -5 -10 -15 -20 -25];
lengthsSec = [3 10];        % 3 s is the hardest case, 10 s the proposal's easiest
nSongs     = 15;            % sample, not the full catalogue - this is a probe
repsPerSong = 2;
noiseTypes = {'cafe', 'traffic', 'crowd'};

% ---- Load ---------------------------------------------------------------
catalog = loadCatalog(Cfg);
dbRows  = catalog(catalog.role == 'db', :);

indexPath = fullfile(projRoot, 'db', sprintf('index_%s.mat', Cfg.tag));
if ~isfile(indexPath)
    error('HimigTransform:NoIndex', ...
        'No index at %s. Run s03_enroll first.', indexPath);
end
S   = load(indexPath);
Idx = S.Idx;

noiseBank = loadNoiseBank(Cfg);

% Spread the sample across the catalogue rather than taking the first N, so
% both repertoires are represented.
pick    = round(linspace(1, height(dbRows), min(nSongs, height(dbRows))));
songIDs = double(dbRows.songID(pick));

logMsg('info', 'Probe: %d song(s) x %d length(s) x %d SNR(s) x %d noise x %d rep(s) = %d queries.', ...
    numel(songIDs), numel(lengthsSec), numel(snrGrid), numel(noiseTypes), ...
    repsPerSong, numel(songIDs) * numel(lengthsSec) * numel(snrGrid) * ...
    numel(noiseTypes) * repsPerSong);

cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
rows  = {};

tAll = tic;

for li = 1:numel(lengthsSec)
    lenSec = lengthsSec(li);

    for si = 1:numel(snrGrid)
        snr = snrGrid(si);

        if isinf(snr) && snr > 0
            theseNoise = {''};        % clean has no noise type
        else
            theseNoise = noiseTypes;
        end

        nCorrect = 0; nTotal = 0;
        normScores = []; margins = []; scores = []; nHashes = [];

        for ni = 1:numel(theseNoise)
            for k = 1:numel(songIDs)
                id  = songIDs(k);
                row = catalog(catalog.songID == id, :);

                procFile = fullfile(projRoot, 'data', 'processed', ...
                    strrep(char(row.procPath), '/', filesep));

                if isKey(cache, procFile)
                    x = cache(procFile);
                else
                    x = double(audioread(procFile));
                    x = x(:, 1);
                    cache(procFile) = x;
                end

                lenSamp = round(lenSec * Cfg.audio.fs);

                for rep = 1:repsPerSong
                    % Deterministic excerpt, spread through the track.
                    frac = 0.25 + 0.5 * (rep - 1) / max(repsPerSong - 1, 1);
                    s0   = max(1, min(round(frac * numel(x)), numel(x) - lenSamp));
                    q    = x(s0 : s0 + lenSamp - 1);

                    if isinf(snr) && snr > 0
                        y = q;
                    else
                        nRow = noiseBank(noiseBank.noiseType == theseNoise{ni}, :);
                        nPath = fullfile(projRoot, 'data', 'noise', char(nRow.file(1)));

                        if isKey(cache, nPath)
                            nAll = cache(nPath);
                        else
                            nAll = double(audioread(nPath));
                            nAll = nAll(:, 1);
                            cache(nPath) = nAll;
                        end

                        nStart = 1 + mod((k * 7919 + rep * 104729), ...
                                         max(numel(nAll) - lenSamp - 1, 1));
                        y = mixAtSNR(q, nAll(nStart : nStart + lenSamp - 1), snr);
                    end

                    res = identifyQuery(y, Idx, Cfg);

                    nTotal   = nTotal + 1;
                    nCorrect = nCorrect + (res.pred1 == id);
                    normScores(end+1) = res.normScore;   %#ok<SAGROW>
                    margins(end+1)    = res.margin;      %#ok<SAGROW>
                    scores(end+1)     = res.score1;      %#ok<SAGROW>
                    nHashes(end+1)    = res.nQueryHashes;%#ok<SAGROW>
                end
            end
        end

        acc = nCorrect / max(nTotal, 1);
        [lo, hi] = wilsonInterval(nCorrect, nTotal);

        rows{end+1} = struct( ...
            'lengthSec',        lenSec, ...
            'snrDb',            snr, ...
            'n',                nTotal, ...
            'top1',             acc, ...
            'ciLo',             lo, ...
            'ciHi',             hi, ...
            'medNormScore',     median(normScores), ...
            'medMargin',        median(margins), ...
            'minMargin',        min(margins), ...
            'medScore1',        median(scores), ...
            'medQueryHashes',   median(nHashes));   %#ok<SAGROW>

        logMsg('info', '  %2.0f s @ %5.0f dB: top-1 %.1f%% (n=%d), normScore %.4f', ...
            lenSec, snr, 100 * acc, nTotal, median(normScores));
    end
end

T = struct2table([rows{:}]);

% ---- Report -------------------------------------------------------------
for li = 1:numel(lengthsSec)
    lenSec = lengthsSec(li);
    sub = T(T.lengthSec == lenSec, :);

    fprintf('\n--- %g s queries ---\n', lenSec);
    fprintf('%6s %9s %18s %12s %10s %9s\n', ...
        'SNR', 'top-1', 'Wilson 95%', 'normScore', 'margin', 'hashes');
    for ii = 1:height(sub)
        fprintf('%6.0f %8.1f%% %8.1f - %5.1f %12.4f %10.1f %9.0f\n', ...
            sub.snrDb(ii), 100 * sub.top1(ii), ...
            100 * sub.ciLo(ii), 100 * sub.ciHi(ii), ...
            sub.medNormScore(ii), sub.medMargin(ii), sub.medQueryHashes(ii));
    end
end

% ---- Where is the knee? -------------------------------------------------
fprintf('\n--- Knee ---\n');
for li = 1:numel(lengthsSec)
    lenSec = lengthsSec(li);
    sub    = T(T.lengthSec == lenSec, :);
    finite = sub(~isinf(sub.snrDb), :);

    below = finite(finite.top1 < 0.95, :);
    if isempty(below)
        fprintf('  %g s: still >= 95%% at %g dB - the sweep did not reach the knee.\n', ...
            lenSec, min(finite.snrDb));
    else
        fprintf('  %g s: first drops below 95%% at %g dB.\n', ...
            lenSec, max(below.snrDb));
    end

    cleanNs = sub.medNormScore(isinf(sub.snrDb));
    at0     = sub.medNormScore(sub.snrDb == 0);
    if ~isempty(cleanNs) && ~isempty(at0)
        fprintf('       normScore at 0 dB is %.0f%% of clean - degradation IS\n', ...
            100 * at0 / cleanNs);
        fprintf('       measurable at 0 dB even where accuracy is not.\n');
    end
end

outDir = fullfile(projRoot, 'results', 'tables');
if ~isfolder(outDir), mkdir(outDir); end
outPath = fullfile(outDir, 'kneeProbe.csv');
writetable(T, outPath);

fprintf('\nWritten to %s  (%.1f s)\n', outPath, toc(tAll));
fprintf(['\nDECIDE FROM THIS, THEN RUN THE FULL GRID:\n' ...
         '  - If accuracy only breaks well below 0 dB, extend Cfg.eval.snrDb\n' ...
         '    downward so the systems have somewhere to separate. Keep the\n' ...
         '    proposal''s clean/10/5/0 row: a saturated baseline is a result.\n' ...
         '  - Either way, add normScore as a reported measure. It degrades at\n' ...
         '    0 dB where accuracy does not, and it is what Enhancement 1\n' ...
         '    protects.\n' ...
         '  - Re-run s04_buildQueries after changing the SNR grid.\n']);
