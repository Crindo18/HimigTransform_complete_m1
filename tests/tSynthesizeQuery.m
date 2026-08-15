function tests = tSynthesizeQuery
%TSYNTHESIZEQUERY Regeneration from a manifest row must be exact and correct.
%
%   Blueprint D2 trades ~1 GB of query WAVs for a 500 KB manifest on the
%   promise that the waveform can be reproduced bit for bit. If that promise
%   fails, two group members comparing results are comparing different audio
%   and nothing in the pipeline says so.
%
%   THE PREVIOUS VERSION TESTED THE ONE ROW THAT PROVES LEAST. It called
%   synthesizeQuery on M(1,:), and row 1 of the manifest is the CLEAN
%   condition - so the function returned at the isinf(targetSnrDb) branch
%   before ever touching a noise file. Every bug on the noise path (a wrong
%   filename, an out-of-range offset, a mixer that never mixes) was invisible
%   to it. These tests exercise a noisy row on purpose.
%
%   Milestone: M3.  Blueprint: section(s) 0 (D2), 2.5, 6.2.
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

firstProc = resolveProcPath(catalog.procPath(1));
bankOk    = isfile(fullfile(setupPaths(), 'db', 'noiseBank.csv'));
testCase.TestData.ready = isfile(firstProc) && bankOk;

if ~testCase.TestData.ready
    return
end

M = buildQueryManifest(catalog, Cfg);
testCase.TestData.M = M;

testCase.TestData.cleanRow = M(find(isinf(M.targetSnrDb), 1), :);

% A noisy row at the hardest SNR in the grid - the case the enhancements are
% judged on and the one most likely to expose a mixing bug.
noisyIdx = find(~isinf(M.targetSnrDb) & M.targetSnrDb == min(M.targetSnrDb), 1);
testCase.TestData.noisyRow = M(noisyIdx, :);
end

function requireReady(testCase)
assumeTrue(testCase, testCase.TestData.ready, ...
    'Processed audio or noise bank not on disk; run s01_ingest and s02_prepareNoise.');
end

% =======================================================================
function testNoisyRowIsBitExactOnRepeat(testCase)
requireReady(testCase);
row = testCase.TestData.noisyRow;

[y1, m1] = synthesizeQuery(row, testCase.TestData.catalog, testCase.TestData.Cfg);
[y2, m2] = synthesizeQuery(row, testCase.TestData.catalog, testCase.TestData.Cfg);

verifyEqual(testCase, y1, y2, ...
    'A noisy query is not bit-exact on regeneration; D2 does not hold.');
verifyEqual(testCase, m1.snrDbMeasured, m2.snrDbMeasured);
end

% =======================================================================
function testRegenerationSurvivesAnIntervalOfRandomness(testCase)
% Reproducibility must come from the manifest row, not from the ambient state
% of the global generator. Disturbing rand between the two calls is the check
% that no hidden rng() dependency crept back in.
requireReady(testCase);
row = testCase.TestData.noisyRow;

y1 = synthesizeQuery(row, testCase.TestData.catalog, testCase.TestData.Cfg);

rng(9999, 'twister');
rand(1000, 1);

y2 = synthesizeQuery(row, testCase.TestData.catalog, testCase.TestData.Cfg);

verifyEqual(testCase, y1, y2, ...
    'Regeneration depends on global random state; it must depend only on the row.');
end

% =======================================================================
function testDoesNotDisturbTheGlobalStream(testCase)
% The reverse direction. Calling rng() inside a function invoked ~17,000 times
% in a grid makes it a hidden side effect on everything else in the session.
requireReady(testCase);

rng(4242, 'twister');
expected = rand(5, 1);

rng(4242, 'twister');
synthesizeQuery(testCase.TestData.noisyRow, testCase.TestData.catalog, testCase.TestData.Cfg);
actual = rand(5, 1);

verifyEqual(testCase, actual, expected, ...
    'synthesizeQuery advanced or reset the global random stream.');
end

% =======================================================================
function testExcerptHasExactlyTheRequestedLength(testCase)
% Silently clamping a window that runs past the end of the track makes
% lengthSec a lie in the results table and bends the length axis of a figure.
requireReady(testCase);
Cfg = testCase.TestData.Cfg;

for row = {testCase.TestData.cleanRow, testCase.TestData.noisyRow}
    r        = row{1};
    y        = synthesizeQuery(r, testCase.TestData.catalog, Cfg);
    expected = round(r.lengthSec * Cfg.audio.fs);
    verifyEqual(testCase, numel(y), expected, ...
        sprintf('queryID %d asked for %g s but got %.3f s.', ...
        double(r.queryID), r.lengthSec, numel(y) / Cfg.audio.fs));
end
end

% =======================================================================
function testMeasuredSnrMatchesTheRowTarget(testCase)
% The end-to-end version of the tMixSNR contract: whatever the manifest asked
% for is what the returned waveform actually carries.
requireReady(testCase);

M     = testCase.TestData.M;
noisy = M(~isinf(M.targetSnrDb), :);
assumeFalse(testCase, isempty(noisy), 'No noisy rows in the manifest.');

% One row per distinct SNR, so the whole grid is covered cheaply.
snrs = unique(noisy.targetSnrDb);
for k = 1:numel(snrs)
    r = noisy(find(noisy.targetSnrDb == snrs(k), 1), :);
    [~, meas] = synthesizeQuery(r, testCase.TestData.catalog, testCase.TestData.Cfg);
    verifyLessThanOrEqual(testCase, abs(meas.snrDbMeasured - r.targetSnrDb), 0.1, ...
        sprintf('queryID %d targeted %g dB but measured %.3f dB.', ...
        double(r.queryID), r.targetSnrDb, meas.snrDbMeasured));
end
end

% =======================================================================
function testNoisyOutputDiffersFromClean(testCase)
% Guards the degenerate pass: a mixer that quietly returns the clean excerpt
% would satisfy every determinism and length assertion above.
requireReady(testCase);

M = testCase.TestData.M;
r = testCase.TestData.noisyRow;

% The clean row sharing this excerpt - same song, length and rep.
same = M(M.songID == r.songID & M.lengthSec == r.lengthSec & ...
         M.rep == r.rep & isinf(M.targetSnrDb), :);
assumeEqual(testCase, height(same), 1, 'Could not find the paired clean row.');

yClean = synthesizeQuery(same, testCase.TestData.catalog, testCase.TestData.Cfg);
yNoisy = synthesizeQuery(r,    testCase.TestData.catalog, testCase.TestData.Cfg);

verifyEqual(testCase, numel(yNoisy), numel(yClean));
verifyGreaterThan(testCase, norm(yNoisy - yClean), 0, ...
    'The noisy query is identical to the clean one; no noise was added.');
end

% =======================================================================
function testOutputDoesNotClip(testCase)
requireReady(testCase);

M     = testCase.TestData.M;
noisy = M(~isinf(M.targetSnrDb), :);
n     = min(20, height(noisy));

for k = 1:n
    y = synthesizeQuery(noisy(k, :), testCase.TestData.catalog, testCase.TestData.Cfg);
    verifyLessThanOrEqual(testCase, max(abs(y)), 1.0, ...
        sprintf('queryID %d clips.', double(noisy.queryID(k))));
end
end
