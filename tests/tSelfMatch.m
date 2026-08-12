function tests = tSelfMatch
%TSELFMATCH A song must identify itself. The smoke test for the whole pipeline.
%
%   If this fails, nothing downstream is worth debugging. It is the M1 exit
%   criterion and it should stay in the suite forever, because it catches
%   almost every asymmetry between the enrolment and query paths.
%
%   Runs on the toy database, not the real one: the toy set exists on every
%   machine, so a member who has not finished downloading the music can still
%   run the merge gate (blueprint 1.4, risk R2).
%
%   Milestone: M1.  Blueprint: sections 5, 7 (M1).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
Cfg = baselineConfig();
testCase.TestData.Cfg = Cfg;

[catalog, sigs] = loadToyCorpus(testCase, Cfg);

dbRows = catalog(catalog.role == 'db', :);
assumeTrue(testCase, height(dbRows) >= 3, ...
    'Need at least 3 enrolled toy songs. Run s00_makeToySet.');

fps = cell(height(dbRows), 1);
for k = 1:height(dbRows)
    fps{k} = extractFingerprint(sigs(double(dbRows.songID(k))), Cfg);
end

testCase.TestData.catalog = catalog;
testCase.TestData.sigs    = sigs;
testCase.TestData.dbRows  = dbRows;
testCase.TestData.Idx     = buildIndex(fps, double(dbRows.songID), Cfg);
end

function testCleanExcerptMatchesItself(testCase)
% CONTRACT: a clean 10 s excerpt of an enrolled song returns that song as
% pred1 with margin > 3, on the toy database.
Cfg    = testCase.TestData.Cfg;
Idx    = testCase.TestData.Idx;
dbRows = testCase.TestData.dbRows;
sigs   = testCase.TestData.sigs;

lenSamp = 10 * Cfg.audio.fs;

for k = 1:height(dbRows)
    id  = double(dbRows.songID(k));
    x   = sigs(id);

    % A fixed interior offset, not the start: the opening of a track is the
    % least characteristic part of it, and starting at sample 1 would also
    % hide any frame-alignment bug, since the query would be perfectly
    % aligned with the reference by construction.
    i0  = floor(numel(x) / 3);
    seg = x(i0 : min(i0 + lenSamp - 1, numel(x)));

    res = identifyQuery(seg, Idx, Cfg);

    verifyEqual(testCase, res.pred1, id, ...
        sprintf('Toy song %d identified as %d.', id, res.pred1));
    verifyGreaterThan(testCase, res.margin, 3, ...
        sprintf('Song %d matched itself with margin %.2f (need > 3).', id, res.margin));
    verifyTrue(testCase, res.accepted, ...
        sprintf('Song %d matched but was rejected by the open-set rule.', id));
end
end

function testOffsetIsRecoveredCorrectly(testCase)
% The alignment histogram must peak at the true excerpt offset. This is the
% test that catches a sign error or an off-by-one in alignOffsets - both of
% which still produce a correct pred1 on a small database, and then quietly
% destroy accuracy at 100 songs where the wrong offset no longer wins.
Cfg  = testCase.TestData.Cfg;
Idx  = testCase.TestData.Idx;
id   = double(testCase.TestData.dbRows.songID(1));
x    = testCase.TestData.sigs(id);

startSample = 7 * Cfg.audio.fs + 137;     % deliberately not a frame boundary
seg = x(startSample : startSample + 10 * Cfg.audio.fs - 1);

res = identifyQuery(seg, Idx, Cfg);

expectedFrames = (startSample - 1) / Cfg.stft.hop;

verifyEqual(testCase, res.pred1, id);
verifyEqual(testCase, res.bestOffsetFrames, expectedFrames, 'AbsTol', 2, ...
    sprintf('Recovered offset %g frames, expected %.1f.', ...
            res.bestOffsetFrames, expectedFrames));
end

function testUnenrolledSongIsNotConfidentlyMatched(testCase)
% CONTRACT: a holdout song must score dramatically weaker than a genuine
% match. That separation is a property of the pipeline and belongs at M1.
%
% WHAT THIS DELIBERATELY DOES NOT ASSERT is that the holdout is REJECTED.
% Rejection depends on tau and rho, which defaultConfig marks "TUNE ON DEV"
% and which blueprint 8.2 says are chosen at M5 on the dev split, across the
% whole SNR grid. Asserting an accept/reject outcome here would be asserting
% an M5 tuning result at M1, and would block the merge gate on a threshold
% nobody has calibrated yet.
%
% Small-database caveat: on a 4-song toy index built from five tracks that
% share one synthesis process, some spurious alignment is expected. What must
% hold is the gap.
Cfg = testCase.TestData.Cfg;
Idx = testCase.TestData.Idx;
catalog = testCase.TestData.catalog;

held = catalog(catalog.role == 'holdout', :);
assumeTrue(testCase, height(held) >= 1, 'No holdout song in the toy catalog.');

% Genuine matches first, so the comparison is against measured behaviour on
% this machine rather than against a number hard-coded from someone else's.
dbRows      = testCase.TestData.dbRows;
genuineNorm = zeros(height(dbRows), 1);
genuineMarg = zeros(height(dbRows), 1);

for k = 1:height(dbRows)
    x   = testCase.TestData.sigs(double(dbRows.songID(k)));
    i0  = floor(numel(x) / 3);
    seg = x(i0 : min(i0 + 10 * Cfg.audio.fs - 1, numel(x)));
    r   = identifyQuery(seg, Idx, Cfg);
    genuineNorm(k) = r.normScore;
    genuineMarg(k) = r.margin;
end

id  = double(held.songID(1));
x   = testCase.TestData.sigs(id);
i0  = floor(numel(x) / 3);
seg = x(i0 : min(i0 + 10 * Cfg.audio.fs - 1, numel(x)));

res = identifyQuery(seg, Idx, Cfg);

log(testCase, 1, sprintf( ...
    ['open-set separation on the toy set:\n' ...
     '  genuine normScore %.4f - %.4f (margin %.1f - %.1f)\n' ...
     '  holdout normScore %.4f          (margin %.1f)\n' ...
     '  current tau = %.3f, rho = %.2f  <- placeholders, tuned on dev at M5'], ...
    min(genuineNorm), max(genuineNorm), min(genuineMarg), max(genuineMarg), ...
    res.normScore, res.margin, Cfg.match.tau, Cfg.match.rho));

% The separation that makes a threshold findable at all. A factor of 3 is a
% loose bar - the observed gap is far wider - so failing it means the matcher
% is genuinely confusing an unenrolled song with an enrolled one.
verifyLessThan(testCase, res.normScore, min(genuineNorm) / 3, ...
    sprintf(['Holdout normScore %.4f is not clearly separated from the weakest ' ...
             'genuine match (%.4f). No tau can split these.'], ...
            res.normScore, min(genuineNorm)));

verifyLessThan(testCase, res.margin, min(genuineMarg), ...
    sprintf('Holdout margin %.2f is not below the weakest genuine margin %.2f.', ...
            res.margin, min(genuineMarg)));
end

function testShorterQueriesStillMatch(testCase)
% 3 s and 5 s on clean audio. Not an accuracy claim - that is M3's job with
% proper statistics - just a check that nothing in the length normalisation
% falls over below 10 s.
Cfg = testCase.TestData.Cfg;
Idx = testCase.TestData.Idx;
id  = double(testCase.TestData.dbRows.songID(1));
x   = testCase.TestData.sigs(id);

for lenSec = [3 5]
    i0  = floor(numel(x) / 3);
    seg = x(i0 : i0 + lenSec * Cfg.audio.fs - 1);
    res = identifyQuery(seg, Idx, Cfg);

    verifyEqual(testCase, res.pred1, id, ...
        sprintf('%d s clean query failed to identify song %d.', lenSec, id));
end
end

function testSilenceReturnsNoMatchRatherThanErroring(testCase)
% The GUI can hand this function a silent recording. It must come back with a
% clean rejection, not an exception.
Cfg = testCase.TestData.Cfg;
Idx = testCase.TestData.Idx;

res = identifyQuery(zeros(10 * Cfg.audio.fs, 1), Idx, Cfg);

verifyFalse(testCase, res.accepted, 'Silence was accepted as a match.');
verifyEqual(testCase, res.pred1, 0);
end

function testMatchTimeIsUnderOneSecond(testCase)
% Success criterion #3, indicatively. The real timing table is M2/M7 with
% warm-up discard and percentiles (blueprint 6.3); this only catches an
% accidental O(n^2) in the online path.
Cfg = testCase.TestData.Cfg;
Idx = testCase.TestData.Idx;
id  = double(testCase.TestData.dbRows.songID(1));
x   = testCase.TestData.sigs(id);
seg = x(1 : 10 * Cfg.audio.fs);

identifyQuery(seg, Idx, Cfg);   % discard the JIT warm-up

res = identifyQuery(seg, Idx, Cfg);

verifyLessThan(testCase, res.tTotalSec, 1.0, ...
    sprintf('Match took %.3f s (hash %.3f, match %.3f).', ...
            res.tTotalSec, res.tHashSec, res.tMatchSec));
end

% =======================================================================
function [catalog, sigs] = loadToyCorpus(testCase, Cfg)
%LOADTOYCORPUS Read the toy catalog and its processed audio into memory.

root    = setupPaths();
catPath = fullfile(root, 'db', 'catalogToy.csv');

assumeTrue(testCase, isfile(catPath), ...
    'db/catalogToy.csv not found. Run s00_makeToySet first.');

catalog = loadCatalog(Cfg, catPath);

sigs = containers.Map('KeyType', 'double', 'ValueType', 'any');

for k = 1:height(catalog)
    f = fullfile(root, 'data', 'toy', 'processed', ...
        strrep(char(catalog.procPath(k)), '/', filesep));
    assumeTrue(testCase, isfile(f), ...
        sprintf('Missing toy audio %s. Re-run s00_makeToySet.', catalog.procPath(k)));
    sigs(double(catalog.songID(k))) = audioread(f);
end

end