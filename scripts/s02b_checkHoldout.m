%S02B_CHECKHOLDOUT  Are any "holdout" songs actually in the database?
%
%   Queries every holdout song against the enrolled index, clean, at several
%   offsets, and reports the best match for each. A holdout song is supposed
%   to be absent from the database, so a strong match means the two sets
%   overlap and the open-set numbers are measuring the wrong thing.
%
%   Usage
%       s02b_checkHoldout
%       s02b_system = 'baseline'; s02b_checkHoldout
%
%   WHY THIS EXISTS. s05 had to push tau to 0.478 to hold FAR under 1%. For
%   scale: a GENUINE in-database query scores about 0.28 clean and 0.14 at
%   0 dB. A threshold above 0.4 means some holdout queries were scoring
%   HIGHER than real matches - and 48% of a query's hashes aligning at one
%   offset is not chance, it is the same recording.
%
%   The likely cause is ordinary and easy to miss: the catalogue was built
%   from personal music libraries, so the same track can appear in both the
%   enrolled folders and the holdout folder - a duplicate file, a remaster, a
%   single and an album cut, or the same song under a different spelling.
%
%   WHAT IT COSTS IF LEFT ALONE. Every duplicate is a query that SHOULD be
%   accepted being counted as a false accept. That inflates FAR, forces tau up
%   to compensate, and the high tau then rejects genuine queries - which is
%   exactly the pattern observed: precision 1.000, FAR 0.000, recall 0.03.
%   The open-set threshold ends up set by a data-cleaning problem rather than
%   by the system.
%
%   Milestone: M5.  Blueprint: sections 2.2, 8.3.
%
%   See also TUNETHRESHOLDS, S01_INGEST, S03_ENROLL.

projRoot = setupPaths();

if ~exist('s02b_system', 'var') || isempty(s02b_system)
    s02b_system = 'baseline';
end

% A holdout query scoring at or above this is not a coincidence. Genuine
% clean in-database queries sit near 0.28, so anything at 0.15 or above is
% sharing a substantial fraction of its fingerprint with an enrolled track.
suspectNormScore = 0.15;

Cfg = systemConfig(s02b_system);
rng(Cfg.seed, 'twister');

logMsg('info', '===== s02b_checkHoldout =====');

indexPath = fullfile(projRoot, 'db', sprintf('index_%s.mat', Cfg.tag));
if ~isfile(indexPath)
    error('HimigTransform:NoIndex', 'No index at %s. Run s03_enroll.', indexPath);
end
S   = load(indexPath);
Idx = S.Idx;

catalog = loadCatalog(Cfg);
hold    = catalog(catalog.role == 'holdout', :);

if isempty(hold)
    error('HimigTransform:NoHoldout', 'No holdout songs in the catalogue.');
end

logMsg('info', 'Probing %d holdout song(s) against %d enrolled song(s).', ...
    height(hold), Idx.stats.nSongsEnrolled);

lenSec  = 10;
offsets = [0.20 0.40 0.60 0.80];   % fractions of the track

rows = {};

for k = 1:height(hold)
    id = double(hold.songID(k));
    f  = fullfile(projRoot, 'data', 'processed', ...
        strrep(char(hold.procPath(k)), '/', filesep));

    x = double(audioread(f));
    x = x(:, 1);

    lenSamp = min(round(lenSec * Cfg.audio.fs), numel(x));

    bestNs   = 0;
    bestPred = 0;
    bestMg   = 0;

    for oi = 1:numel(offsets)
        s0 = max(1, min(round(offsets(oi) * numel(x)), numel(x) - lenSamp + 1));
        res = identifyQuery(x(s0 : s0 + lenSamp - 1), Idx, Cfg);

        if res.normScore > bestNs
            bestNs   = res.normScore;
            bestPred = res.pred1;
            bestMg   = res.margin;
        end
    end

    if bestPred > 0
        matchRow   = catalog(catalog.songID == bestPred, :);
        matchTitle = char(matchRow.title(1));
        matchArtist = char(matchRow.artist(1));
    else
        matchTitle  = '-';
        matchArtist = '-';
    end

    rows{end+1} = struct( ...
        'holdoutID',     id, ...
        'holdoutTitle',  string(hold.title(k)), ...
        'holdoutArtist', string(hold.artist(k)), ...
        'bestMatchID',   bestPred, ...
        'bestMatchTitle', string(matchTitle), ...
        'bestMatchArtist', string(matchArtist), ...
        'normScore',     bestNs, ...
        'margin',        bestMg, ...
        'suspect',       bestNs >= suspectNormScore); %#ok<SAGROW>
end

T = struct2table([rows{:}]);
T = sortrows(T, 'normScore', 'descend');

fprintf('\n--- Holdout songs, best match against the enrolled database ---\n');
fprintf('%9s %10s %8s   %-28s -> %s\n', ...
    'holdoutID', 'normScore', 'margin', 'holdout title', 'best enrolled match');

for ii = 1:height(T)
    if T.suspect(ii)
        mark = '  <-- DUPLICATE?';
    else
        mark = '';
    end
    fprintf('%9d %10.4f %8.1f   %-28s -> %s%s\n', ...
        T.holdoutID(ii), T.normScore(ii), T.margin(ii), ...
        truncate(char(T.holdoutTitle(ii)), 28), ...
        truncate(char(T.bestMatchTitle(ii)), 28), mark);
end

nSuspect = nnz(T.suspect);

fprintf('\n--- Verdict ---\n');
fprintf('  holdout songs        : %d\n', height(T));
fprintf('  suspected duplicates : %d  (normScore >= %.2f)\n', nSuspect, suspectNormScore);
fprintf('  max holdout normScore: %.4f\n', max(T.normScore));

if nSuspect > 0
    fprintf(['\n  These are not open-set failures - they are catalogue errors.\n' ...
             '  Each one is a query that SHOULD match being counted as a false\n' ...
             '  accept, which inflates FAR and forces tau up until genuine\n' ...
             '  queries get rejected too.\n\n' ...
             '  Fix: remove the duplicate from data/raw/holdout (or from the\n' ...
             '  enrolled folder, whichever copy is the stray), re-run\n' ...
             '  s01_ingest, s03_enroll, s04_buildQueries, then re-tune at s05.\n' ...
             '  songID is never reused, so the manifest must be rebuilt.\n']);
else
    fprintf(['\n  No duplicates. The open-set difficulty is real, not a data\n' ...
             '  problem - report the operating characteristic rather than a\n' ...
             '  single point, and pick the FAR budget from the knee.\n']);
end

outDir = fullfile(projRoot, 'results', 'tables');
if ~isfolder(outDir), mkdir(outDir); end
outPath = fullfile(outDir, 'holdoutCheck.csv');
writetable(T, outPath);

fprintf('\nWritten to %s\n', outPath);
fprintf('s02b_checkHoldout: PASS\n');
fprintf('---------------------\n');

% =======================================================================
function s = truncate(s, n)
if numel(s) > n
    s = [s(1:n-3) '...'];
end
end
