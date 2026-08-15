function tests = tQueryManifest
%TQUERYMANIFEST The manifest is the experiment design, so it is tested as one.
%
%   Blueprint D2 stores no query WAVs: this table plus SYNTHESIZEQUERY IS the
%   query set. Every property the statistics in 8.4 rely on lives here, and
%   none of them is visible by eye in a 17,000-row table.
%
%   THE PREVIOUS VERSION OF THIS FILE COULD NOT FAIL. It guarded with
%   isfile(dbSongs.procPath{1}) on the catalog's RELATIVE path, which is false
%   from the project root whether or not the audio exists - so the test hit
%   assumeFail every run and was reported as passing-because-filtered. That is
%   the same shape as the three assumeFail tests the M2 review found in
%   tIndexBackendParity. A test that cannot fail is worse than no test,
%   because it occupies the slot where a real one would go.
%
%   The guard here resolves the path properly, so it skips only when the audio
%   is genuinely absent and runs whenever it is present.
%
%   Milestone: M3.  Blueprint: section(s) 2.5, 8.1, 8.2, 8.4.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
Cfg = baselineConfig();
testCase.TestData.Cfg = Cfg;

if ~isfile(fullfile(setupPaths(), 'db', 'catalog.csv'))
    testCase.TestData.ready = false;
    return
end

catalog = loadCatalog();
testCase.TestData.catalog = catalog;

% Resolve the path the way every consumer does, not the way the CSV stores it.
firstProc = resolveProcPath(catalog.procPath(1));
bankOk    = isfile(fullfile(setupPaths(), 'db', 'noiseBank.csv'));

testCase.TestData.ready = isfile(firstProc) && bankOk;

if testCase.TestData.ready
    testCase.TestData.M = buildQueryManifest(catalog, Cfg);
end
end

function requireReady(testCase)
assumeTrue(testCase, testCase.TestData.ready, ...
    'Processed audio or noise bank not on disk; run s01_ingest and s02_prepareNoise.');
end

% =======================================================================
function testExcerptIsSharedAcrossEveryNoiseCondition(testCase)
% INVARIANT (a), blueprint 2.5. The same (songID, lengthSec, rep) must carry
% one startSample across all conditions - that is what pairs the systems and
% licenses McNemar.
requireReady(testCase);
M = testCase.TestData.M;

G = findgroups(M.songID, M.lengthSec, M.rep);
n = splitapply(@(s) numel(unique(s)), M.startSample, G);

verifyEqual(testCase, n, ones(size(n)), ...
    'startSample varies within a (songID, lengthSec, rep) group.');
end

% =======================================================================
function testNoiseSegmentIsSharedAcrossSnr(testCase)
% INVARIANT (b). Redrawing the noise offset per SNR leaves McNemar valid but
% confounds the SNR axis: the drop from 10 dB to 0 dB would mix "worse SNR"
% with "different babble", and that axis is a headline figure.
requireReady(testCase);
M = testCase.TestData.M;

noisy = M(M.noiseType ~= 'none', :);
assumeFalse(testCase, isempty(noisy), 'No noisy rows to check.');

G = findgroups(noisy.songID, noisy.lengthSec, noisy.rep, noisy.noiseType);
n = splitapply(@(s) numel(unique(s)), noisy.noiseStartSample, G);

verifyEqual(testCase, n, ones(size(n)), ...
    ['noiseStartSample varies across SNR within one (song, length, rep, ' ...
     'noiseType) group; the SNR axis is confounded.']);
end

% =======================================================================
function testHoldoutSongsAreQueried(testCase)
% Without holdout rows there is no FAR, the precision denominator in 8.3 loses
% its wrongly-accepted term, and M5 has no ROC to tune tau and rho on.
requireReady(testCase);
M       = testCase.TestData.M;
catalog = testCase.TestData.catalog;

nHoldCatalog  = nnz(catalog.role == 'holdout');
assumeGreaterThan(testCase, nHoldCatalog, 0, 'Catalog has no holdout songs.');

nHoldQueried = numel(unique(M.songID(M.role == 'holdout')));
verifyEqual(testCase, nHoldQueried, nHoldCatalog, ...
    'Not every holdout song appears in the manifest.');
end

% =======================================================================
function testGridSizeMatchesTheConfiguredFactorial(testCase)
requireReady(testCase);
M   = testCase.TestData.M;
Cfg = testCase.TestData.Cfg;

snrFinite   = Cfg.eval.snrDb(~isinf(Cfg.eval.snrDb));
nPerExcerpt = 1 + numel(Cfg.eval.noiseTypes) * numel(snrFinite);
expected    = height(testCase.TestData.catalog) * numel(Cfg.eval.lengthsSec) ...
            * Cfg.eval.repsPerSong * nPerExcerpt;

verifyEqual(testCase, height(M), expected, ...
    'Manifest row count does not match lengths x reps x conditions x songs.');
verifyEqual(testCase, numel(unique(M.queryID)), height(M), ...
    'queryID is the primary key and must be unique.');
end

% =======================================================================
function testEveryNoiseFileExistsOnDisk(testCase)
% The filename is looked up from noiseBank.csv rather than derived from the
% noise type. Deriving it produced CAFE_ch01_8k.wav against a bank holding
% PCAFETER_ch01_8k.wav, which would have made every noisy query in the grid
% unloadable - and no clean-only test would have noticed.
requireReady(testCase);
M = testCase.TestData.M;

files = unique(M.noiseFile(M.noiseType ~= 'none'));
verifyNotEmpty(testCase, files, 'No noise files referenced by the manifest.');

noiseRoot = fullfile(setupPaths(), 'data', 'noise');
for k = 1:numel(files)
    f = fullfile(noiseRoot, char(files(k)));
    verifyTrue(testCase, isfile(f), ...
        sprintf('Manifest references a noise file that does not exist: %s', f));
end
end

% =======================================================================
function testNoiseOffsetsSpanTheWholeBank(testCase)
% An earlier version drew the offset with randi(8000*10), capping it at the
% first 10 s of a 300 s recording. Every query of a given type then heard
% nearly the same babble, and 97% of the bank went unused.
requireReady(testCase);
M   = testCase.TestData.M;
Cfg = testCase.TestData.Cfg;

bank  = loadNoiseBank(Cfg);
noisy = M(M.noiseType ~= 'none', :);

for k = 1:height(bank)
    sel = noisy(noisy.noiseType == bank.noiseType(k), :);
    if isempty(sel), continue; end

    maxSeen  = double(max(sel.noiseStartSample));
    bankSpan = double(bank.nSamples(k));

    verifyGreaterThan(testCase, maxSeen, 0.25 * bankSpan, ...
        sprintf(['Noise offsets for "%s" never exceed %.0f%% of the %.0f s bank; ' ...
                 'the draw range is too narrow.'], ...
                 char(bank.noiseType(k)), 100 * maxSeen / bankSpan, ...
                 bankSpan / Cfg.audio.fs));
end
end

% =======================================================================
function testSplitIsAssignedAtSongLevel(testCase)
% Blueprint 8.2: split at the SONG level. A song appearing in both dev and
% test is the leak that makes every tuned threshold indefensible.
requireReady(testCase);
M = testCase.TestData.M;

G = findgroups(M.songID);
n = splitapply(@(s) numel(unique(s)), string(M.split), G);

verifyEqual(testCase, n, ones(size(n)), ...
    'A songID appears under more than one split - that is query-level leakage.');
end

% =======================================================================
function testManifestIsReproducible(testCase)
% D2 rests entirely on this: the manifest is stored instead of ~1 GB of WAVs,
% so rebuilding it must give the same table.
requireReady(testCase);

M2 = buildQueryManifest(testCase.TestData.catalog, testCase.TestData.Cfg);

verifyEqual(testCase, height(M2), height(testCase.TestData.M));
verifyEqual(testCase, M2.startSample, testCase.TestData.M.startSample, ...
    'Rebuilding the manifest produced different excerpt starts.');
verifyEqual(testCase, M2.noiseStartSample, testCase.TestData.M.noiseStartSample, ...
    'Rebuilding the manifest produced different noise offsets.');
verifyEqual(testCase, M2.seed, testCase.TestData.M.seed, ...
    'Rebuilding the manifest produced different per-row seeds.');
end
